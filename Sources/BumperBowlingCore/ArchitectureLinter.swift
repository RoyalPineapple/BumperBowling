import Foundation

public struct ArchitectureLinter: Sendable {
    private let rules: ArchitectureRules

    public init(configuration: ArchitectureConfiguration) throws {
        self.rules = try ArchitectureRules(configuration: configuration)
    }

    public init(rules: ArchitectureRules) {
        self.rules = rules
    }

    public func lint(_ facts: RepositoryFacts) -> LintReport {
        let registry = RuleRegistry(configuration: rules.ruleConfiguration)
        let graph = ArchitectureGraph(facts: facts, rules: rules)
        let violations = registry.enabledRules.flatMap { rule in
            rule.evaluate(graph: graph, rules: rules)
        }

        return LintReport(violations: violations)
    }
}

public struct RuleRegistry: Sendable {
    public let enabledRules: [ArchitectureRule]

    public init(configuration: RuleConfiguration) {
        self.enabledRules = [
            .forbiddenImport(configuration.forbiddenImports),
            .subsystemBoundary(configuration.subsystemBoundary),
            .duplicateOwnership(configuration.duplicateOwnership),
            .declaredDependencyCycle(configuration.declaredDependencyCycle),
            .storedProperties(configuration.storedProperties),
            .syntaxConstructs(configuration.syntaxConstructs),
            .syntaxKinds(configuration.syntaxKinds),
            .publicDeclarations(configuration.publicDeclarations),
            .enumStateMachine(configuration.enumStateMachine),
        ].filter(\.isEnabled)
    }
}

public enum ArchitectureRule: Sendable {
    case forbiddenImport([RuleSetting])
    case subsystemBoundary(Severity)
    case duplicateOwnership(Severity)
    case declaredDependencyCycle(Severity)
    case storedProperties(StoredPropertyRuleConfiguration)
    case syntaxConstructs(SyntaxConstructRuleConfiguration)
    case syntaxKinds(SyntaxKindRuleConfiguration)
    case publicDeclarations(PublicDeclarationRuleConfiguration)
    case enumStateMachine(PathRuleConfiguration)

    public var id: RuleID {
        switch self {
        case .forbiddenImport:
            .forbiddenImport
        case .subsystemBoundary:
            .subsystemBoundary
        case .duplicateOwnership:
            .duplicateOwnership
        case .declaredDependencyCycle:
            .declaredDependencyCycle
        case .storedProperties:
            .storedProperties
        case .syntaxConstructs:
            .syntaxConstructs
        case .syntaxKinds:
            .syntaxKinds
        case .publicDeclarations:
            .publicDeclarations
        case .enumStateMachine:
            .enumStateMachine
        }
    }

    public var description: String {
        switch self {
        case .forbiddenImport:
            "Disallows configured imports in linted source files."
        case .subsystemBoundary:
            "Requires subsystem imports to match declared dependencies."
        case .duplicateOwnership:
            "Disallows duplicate subsystem path and module ownership."
        case .declaredDependencyCycle:
            "Disallows cycles in declared subsystem dependencies."
        case .storedProperties:
            "Applies configured assertions over SwiftSyntax stored property facts."
        case .syntaxConstructs:
            "Applies configured assertions over SwiftSyntax construct facts."
        case .syntaxKinds:
            "Applies configured assertions over observed SwiftSyntax node kinds."
        case .publicDeclarations:
            "Applies configured assertions over public declaration facts."
        case .enumStateMachine:
            "Requires parser files to declare an enum state machine."
        }
    }

    var isEnabled: Bool {
        severity != .off
    }

    private var severity: Severity {
        switch self {
        case .forbiddenImport(let settings):
            settings.map(\.severity).reduce(.off) { partialResult, severity in
                partialResult.merging(severity)
            }
        case .subsystemBoundary(let severity):
            severity
        case .duplicateOwnership(let severity):
            severity
        case .declaredDependencyCycle(let severity):
            severity
        case .storedProperties(let configuration):
            configuration.severity
        case .syntaxConstructs(let configuration):
            configuration.severity
        case .syntaxKinds(let configuration):
            configuration.severity
        case .publicDeclarations(let configuration):
            configuration.severity
        case .enumStateMachine(let configuration):
            configuration.severity
        }
    }

    func evaluate(graph: ArchitectureGraph, rules: ArchitectureRules) -> [ArchitectureViolation] {
        switch self {
        case .forbiddenImport(let settings):
            evaluateForbiddenImports(graph: graph, settings: settings)
        case .subsystemBoundary(let severity):
            evaluateSubsystemBoundaries(graph: graph, rules: rules, severity: severity)
        case .duplicateOwnership(let severity):
            evaluateDuplicateOwnership(rules: rules, severity: severity)
        case .declaredDependencyCycle(let severity):
            evaluateDeclaredDependencyCycles(graph: graph, rules: rules, severity: severity)
        case .storedProperties(let configuration):
            evaluateStoredProperties(graph: graph, configuration: configuration)
        case .syntaxConstructs(let configuration):
            evaluateSyntaxConstructs(graph: graph, configuration: configuration)
        case .syntaxKinds(let configuration):
            evaluateSyntaxKinds(graph: graph, configuration: configuration)
        case .publicDeclarations(let configuration):
            evaluatePublicDeclarations(graph: graph, configuration: configuration)
        case .enumStateMachine(let configuration):
            evaluateEnumStateMachines(graph: graph, configuration: configuration)
        }
    }

    private func evaluateForbiddenImports(graph: ArchitectureGraph, settings: [RuleSetting]) -> [ArchitectureViolation] {
        settings.flatMap { setting in
            let forbiddenImports = Set((try? setting.values.map(ModuleName.init)) ?? [])
            let scopedPaths = (try? setting.paths.map(RelativePathPrefix.init)) ?? []

            return graph.sourceFiles.flatMap { file in
                guard scopedPaths.isEmpty || scopedPaths.contains(where: { $0.contains(file.path) }) else {
                    return [ArchitectureViolation]()
                }

                return file.imports.compactMap { importedModule in
                    guard forbiddenImports.contains(importedModule) else {
                        return nil
                    }

                    return violation(
                        severity: setting.severity,
                        path: file.path,
                        message: "\(file.subsystem) imports forbidden module \(importedModule)"
                    )
                }
            }
        }
    }

    private func evaluateSubsystemBoundaries(
        graph: ArchitectureGraph,
        rules: ArchitectureRules,
        severity: Severity
    ) -> [ArchitectureViolation] {
        let subsystemByName = rules.subsystemByID
        var violations: [ArchitectureViolation] = []

        for edge in graph.subsystemImportEdges {
            guard let sourceSubsystem = subsystemByName[edge.sourceSubsystem] else {
                continue
            }

            if sourceSubsystem.forbiddenDependencies.contains(edge.targetSubsystem) {
                violations.append(
                    violation(
                        severity: severity,
                        path: edge.sourcePath,
                        message: "\(edge.sourceSubsystem) must not depend on \(edge.importedModule) (\(edge.targetSubsystem.rawValue))"
                    )
                )
            } else if !sourceSubsystem.allowedDependencies.contains(edge.targetSubsystem),
                      edge.targetSubsystem != edge.sourceSubsystem {
                violations.append(
                    violation(
                        severity: severity,
                        path: edge.sourcePath,
                        message: "\(edge.sourceSubsystem) imports undeclared subsystem \(edge.importedModule) (\(edge.targetSubsystem.rawValue))"
                    )
                )
            }
        }

        return violations
    }

    private func evaluateDeclaredDependencyCycles(
        graph architectureGraph: ArchitectureGraph,
        rules: ArchitectureRules,
        severity: Severity
    ) -> [ArchitectureViolation] {
        let graph = Dictionary(
            uniqueKeysWithValues: rules.subsystems.map { subsystem in
                (subsystem.id, subsystem.allowedDependencies)
            }
        )

        for subsystem in rules.subsystems {
            if reaches(subsystem.id, from: subsystem.id, graph: graph, visited: []) {
                let path = firstPath(for: subsystem.id, graph: architectureGraph, rules: rules)
                return [
                    violation(
                        severity: severity,
                        path: path,
                        message: "Declared dependency cycle includes subsystem \(subsystem.id.rawValue)"
                    ),
                ]
            }
        }

        return []
    }

    private func evaluateDuplicateOwnership(
        rules: ArchitectureRules,
        severity: Severity
    ) -> [ArchitectureViolation] {
        rules.pathOwnershipConflicts.map { conflict in
            violation(
                severity: severity,
                path: conflict.path.asFilePath ?? fallbackPath,
                message: "\(conflict.owner) path \(conflict.path) overlaps \(conflict.overlappingOwner) path \(conflict.overlappingPath)"
            )
        }
    }

    private func reaches(
        _ target: SubsystemID,
        from current: SubsystemID,
        graph: [SubsystemID: Set<SubsystemID>],
        visited: Set<SubsystemID>
    ) -> Bool {
        let dependencies = graph[current] ?? []
        if dependencies.contains(target), !visited.isEmpty {
            return true
        }

        let nextVisited = visited.union([current])
        for dependency in dependencies where !nextVisited.contains(dependency) {
            if reaches(target, from: dependency, graph: graph, visited: nextVisited) {
                return true
            }
        }

        return false
    }

    private func evaluateStoredProperties(
        graph: ArchitectureGraph,
        configuration: StoredPropertyRuleConfiguration
    ) -> [ArchitectureViolation] {
        let paths = (try? configuration.paths.map(RelativePathPrefix.init)) ?? []

        return graph.sourceFiles.flatMap { file in
            guard paths.isEmpty || paths.contains(where: { $0.contains(file.path) }) else {
                return [ArchitectureViolation]()
            }

            return file.storedProperties.flatMap { property in
                storedPropertyViolations(
                    file: file,
                    property: property,
                    configuration: configuration
                )
            }
        }
    }

    private func evaluateSyntaxConstructs(
        graph: ArchitectureGraph,
        configuration: SyntaxConstructRuleConfiguration
    ) -> [ArchitectureViolation] {
        let paths = (try? configuration.paths.map(RelativePathPrefix.init)) ?? []
        let excludedPaths = (try? configuration.excludedPaths.map(RelativePathPrefix.init)) ?? []

        return graph.sourceFiles.flatMap { file in
            guard paths.isEmpty || paths.contains(where: { $0.contains(file.path) }) else {
                return [ArchitectureViolation]()
            }

            guard !excludedPaths.contains(where: { $0.contains(file.path) }) else {
                return [ArchitectureViolation]()
            }

            return file.imperativeConstructs.compactMap { construct in
                guard configuration.disallowedConstructs.contains(construct) else {
                    return nil
                }

                return violation(
                    severity: configuration.severity,
                    path: file.path,
                    message: "Uses imperative construct \(construct.rawValue)"
                )
            }
        }
    }

    private func evaluateSyntaxKinds(
        graph: ArchitectureGraph,
        configuration: SyntaxKindRuleConfiguration
    ) -> [ArchitectureViolation] {
        let paths = (try? configuration.paths.map(RelativePathPrefix.init)) ?? []

        return graph.sourceFiles.flatMap { file in
            guard paths.isEmpty || paths.contains(where: { $0.contains(file.path) }) else {
                return [ArchitectureViolation]()
            }

            let missingRequiredKinds = configuration.requiredKinds
                .subtracting(file.syntaxFacts.nodeKinds)
                .map { kind in
                    violation(
                        severity: configuration.severity,
                        path: file.path,
                        message: "Missing required SwiftSyntax node kind \(kind)"
                    )
                }

            let disallowedKinds = configuration.disallowedKinds
                .intersection(file.syntaxFacts.nodeKinds)
                .map { kind in
                    violation(
                        severity: configuration.severity,
                        path: file.path,
                        message: "Uses disallowed SwiftSyntax node kind \(kind)"
                    )
                }

            return missingRequiredKinds + disallowedKinds
        }
    }

    private func evaluatePublicDeclarations(
        graph: ArchitectureGraph,
        configuration: PublicDeclarationRuleConfiguration
    ) -> [ArchitectureViolation] {
        let paths = (try? configuration.paths.map(RelativePathPrefix.init)) ?? []
        let scopedFiles = graph.sourceFiles.filter { file in
            paths.isEmpty || paths.contains(where: { $0.contains(file.path) })
        }
        let declaredNames = scopedFiles.flatMap { file in
            file.publicDeclarations.map(\.name)
        }
        let missingRequiredNames = configuration.requiredNames
            .filter { matcher in
                !declaredNames.contains { matcher.matches($0) }
            }
            .sorted { $0.description < $1.description }
            .map { matcher in
                violation(
                    severity: configuration.severity,
                    path: scopedFiles.first?.path ?? paths.first?.asFilePath ?? fallbackPath,
                    message: "Missing required public declaration \(matcher)"
                )
            }

        let disallowedNames: [ArchitectureViolation] = scopedFiles.flatMap { file -> [ArchitectureViolation] in
            file.publicDeclarations.compactMap { declaration -> ArchitectureViolation? in
                guard configuration.disallowedNames.contains(where: { $0.matches(declaration.name) }) else {
                    return nil
                }

                return violation(
                    severity: configuration.severity,
                    path: file.path,
                    message: "Public declaration \(declaration.name.rawValue) is disallowed"
                )
            }
        }

        return missingRequiredNames + disallowedNames
    }

    private func storedPropertyViolations(
        file: SourceFileFacts,
        property: StoredProperty,
        configuration: StoredPropertyRuleConfiguration
    ) -> [ArchitectureViolation] {
        var violations: [ArchitectureViolation] = []
        let typeName = property.type?.rawValue ?? ""

        if configuration.disallowances.contains(.storedProperty) {
            violations.append(
                violation(
                    severity: configuration.severity,
                    path: file.path,
                    message: "Stored property \(property.name.rawValue) is stored"
                )
            )
        }

        if configuration.disallowances.contains(.storedVar), property.isMutable {
            violations.append(
                violation(
                    severity: configuration.severity,
                    path: file.path,
                    message: "Stored property \(property.name.rawValue) is mutable"
                )
            )
        }

        if configuration.disallowances.contains(.any), StringMatcher.exact("Any").matches(typeName) {
            violations.append(
                violation(
                    severity: configuration.severity,
                    path: file.path,
                    message: "Stored property \(property.name.rawValue) uses Any"
                )
            )
        }

        if configuration.disallowances.contains(.broadExistential), StringMatcher.prefix("any ").matches(typeName) {
            violations.append(
                violation(
                    severity: configuration.severity,
                    path: file.path,
                    message: "Stored property \(property.name.rawValue) uses a broad existential"
                )
            )
        }

        if configuration.disallowances.contains(.rawStringIdentity), StringMatcher.exact("String").matches(typeName) {
            violations.append(
                violation(
                    severity: configuration.severity,
                    path: file.path,
                    message: "Stored property \(property.name.rawValue) uses raw String"
                )
            )
        }

        return violations
    }

    private func evaluateEnumStateMachines(
        graph: ArchitectureGraph,
        configuration: PathRuleConfiguration
    ) -> [ArchitectureViolation] {
        graph.sourceFiles.compactMap { file in
            guard matchesAny(configuration.paths, file.path) else {
                return nil
            }

            guard !file.enums.contains(where: { StringMatcher.suffix("State").matches($0) }) else {
                return nil
            }

            return violation(
                severity: configuration.severity,
                path: file.path,
                message: "Parser file does not declare an enum state machine"
            )
        }
    }

    private func matchesAny(_ patterns: [String], _ path: RelativeFilePath) -> Bool {
        patterns.contains { pattern in
            matches(pattern: pattern, path: path.rawValue)
        }
    }

    private func matches(pattern: String, path: String) -> Bool {
        if StringMatcher.contains("**/*").matches(pattern) {
            let parts = pattern.components(separatedBy: "**/*")
            let prefix = parts.first ?? ""
            let suffix = parts.dropFirst().joined(separator: "**/*")
            let prefixMatches = prefix.isEmpty || StringMatcher.prefix(prefix).matches(path)
            let suffixMatches = suffix.isEmpty || StringMatcher.suffix(suffix).matches(path)
            return prefixMatches && suffixMatches
        }

        if StringMatcher.suffix("*").matches(pattern) {
            let prefix = String(pattern.dropLast())
            return prefix.isEmpty || StringMatcher.prefix(prefix).matches(path)
        }

        return StringMatcher.exact(pattern).matches(path) || StringMatcher.prefix(pattern + "/").matches(path)
    }

    private func firstPath(
        for subsystem: SubsystemID,
        graph: ArchitectureGraph,
        rules: ArchitectureRules
    ) -> RelativeFilePath {
        if let file = graph.sourceFiles.first(where: { $0.subsystem == subsystem }) {
            return file.path
        }

        if let prefix = rules.subsystemByID[subsystem]?.paths.sorted(by: { $0.rawValue < $1.rawValue }).first,
           let path = try? RelativeFilePath(prefix.rawValue) {
            return path
        }

        return fallbackPath
    }

    private var fallbackPath: RelativeFilePath {
        guard let path = try? RelativeFilePath("Package.swift") else {
            preconditionFailure("Invalid built-in fallback path")
        }
        return path
    }

    private func violation(
        severity: Severity,
        path: RelativeFilePath,
        message: String
    ) -> ArchitectureViolation {
        ArchitectureViolation(
            ruleID: id,
            severity: severity,
            path: path,
            message: message
        )
    }
}

private extension RelativePathPrefix {
    var asFilePath: RelativeFilePath? {
        try? RelativeFilePath(rawValue)
    }
}

public struct LintReport: Equatable, Sendable, Codable {
    public let violations: [ArchitectureViolation]

    public init(violations: [ArchitectureViolation]) {
        self.violations = violations
    }

    public var hasErrors: Bool {
        violations.contains { $0.severity == .error }
    }

    public var markdownSummary: String {
        if violations.isEmpty {
            return "Result: Strike\n\nNo architecture violations found."
        }

        var lines = [hasErrors ? "Result: Gutter Ball" : "Result: Strike", ""]
        for violation in violations {
            lines.append(
                "- [\(violation.severity.rawValue.uppercased())] \(violation.path.rawValue): \(violation.message) (\(violation.ruleID.rawValue))"
            )
        }
        return lines.joined(separator: "\n")
    }
}

public struct ArchitectureViolation: Equatable, Sendable, Codable {
    public let ruleID: RuleID
    public let severity: Severity
    public let path: RelativeFilePath
    public let message: String

    public init(ruleID: RuleID, severity: Severity, path: RelativeFilePath, message: String) {
        self.ruleID = ruleID
        self.severity = severity
        self.path = path
        self.message = message
    }
}

public enum RuleID: String, CaseIterable, Equatable, Sendable, Codable {
    case forbiddenImport = "forbidden_import"
    case subsystemBoundary = "subsystem_boundary"
    case duplicateOwnership = "duplicate_ownership"
    case declaredDependencyCycle = "declared_dependency_cycle"
    case storedProperties = "stored_properties"
    case syntaxConstructs = "syntax_constructs"
    case syntaxKinds = "syntax_kinds"
    case publicDeclarations = "public_declarations"
    case enumStateMachine = "enum_state_machine"
}

public enum Severity: String, Equatable, Sendable, Codable {
    case off
    case note
    case warning
    case error
}
