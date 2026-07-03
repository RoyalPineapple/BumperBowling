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
            return graph.imports(in: scope(paths: setting.paths)).compactMap { importFact -> ArchitectureViolation? in
                guard forbiddenImports.contains(importFact.module) else {
                    return nil
                }

                return violation(
                    severity: setting.severity,
                    path: importFact.file.path,
                    message: "\(importFact.file.subsystem) imports forbidden module \(importFact.module)"
                )
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
        let excludedPaths = (try? configuration.excludedPaths.map(RelativePathPrefix.init)) ?? []

        return graph.storedProperties(in: scope(paths: configuration.paths)).flatMap { propertyFact -> [ArchitectureViolation] in
            guard !excludedPaths.contains(where: { $0.contains(propertyFact.file.path) }) else {
                return []
            }

            return storedPropertyViolations(
                file: propertyFact.file,
                property: propertyFact.property,
                graph: graph,
                configuration: configuration
            )
        }
    }

    private func evaluateSyntaxConstructs(
        graph: ArchitectureGraph,
        configuration: SyntaxConstructRuleConfiguration
    ) -> [ArchitectureViolation] {
        let excludedPaths = (try? configuration.excludedPaths.map(RelativePathPrefix.init)) ?? []

        return graph.constructs(in: scope(paths: configuration.paths)).compactMap { constructFact -> ArchitectureViolation? in
            guard !excludedPaths.contains(where: { $0.contains(constructFact.file.path) }) else {
                return nil
            }

            guard configuration.disallowedConstructs.contains(constructFact.construct.construct) else {
                return nil
            }

            return violation(
                severity: configuration.severity,
                path: constructFact.file.path,
                message: "Uses imperative construct \(constructFact.construct.construct.rawValue)",
                location: constructFact.construct.location,
                evidence: ViolationEvidence(
                    observed: "imperative construct \(constructFact.construct.construct.rawValue)",
                    expectation: "disallowed constructs: \(configuration.disallowedConstructs.map(\.rawValue).sorted().joined(separator: ", "))"
                )
            )
        }
    }

    private func evaluateSyntaxKinds(
        graph: ArchitectureGraph,
        configuration: SyntaxKindRuleConfiguration
    ) -> [ArchitectureViolation] {
        graph.files(in: scope(paths: configuration.paths)).flatMap { file in
            let observedKinds = Set(file.syntaxFacts.nodeKinds.map(SyntaxKindName.init))
            let missingRequiredKinds = configuration.requiredKinds
                .subtracting(observedKinds)
                .map { kind in
                    violation(
                        severity: configuration.severity,
                        path: file.path,
                        message: "Missing required SwiftSyntax node kind \(kind)"
                    )
                }

            let disallowedKinds = configuration.disallowedKinds
                .intersection(observedKinds)
                .map { kind in
                    let fact = file.syntaxFacts.facts.first { SyntaxKindName($0.nodeKind) == kind }
                    let expectedKinds = configuration.disallowedKinds
                        .map(\.rawValue)
                        .sorted()
                        .joined(separator: ", ")
                    return violation(
                        severity: configuration.severity,
                        path: file.path,
                        message: "Uses disallowed SwiftSyntax node kind \(kind)",
                        location: fact?.location,
                        evidence: ViolationEvidence(
                            observed: "SwiftSyntax node kind \(kind)",
                            expectation: "disallowed SwiftSyntax node kinds: \(expectedKinds)"
                        )
                    )
                }

            return missingRequiredKinds + disallowedKinds
        }
    }

    private func evaluatePublicDeclarations(
        graph: ArchitectureGraph,
        configuration: PublicDeclarationRuleConfiguration
    ) -> [ArchitectureViolation] {
        let scope = scope(paths: configuration.paths)
        let scopedFiles = graph.files(in: scope)
        let scopedDeclarations = graph.declarations(in: scope)
        let declaredNames = scopedDeclarations.map(\.declaration.name)
        let missingRequiredNames = configuration.requiredNames
            .filter { matcher in
                !declaredNames.contains { matcher.matches($0) }
            }
            .sorted { $0.description < $1.description }
            .map { matcher in
                    violation(
                        severity: configuration.severity,
                        path: scopedFiles.first?.path ?? firstPath(in: scope) ?? fallbackPath,
                        message: "Missing required public declaration \(matcher)"
                    )
                }

        let disallowedNames: [ArchitectureViolation] = scopedDeclarations.compactMap { declarationFact -> ArchitectureViolation? in
            guard configuration.disallowedNames.contains(where: { $0.matches(declarationFact.declaration.name) }) else {
                return nil
            }

            return violation(
                severity: configuration.severity,
                path: declarationFact.file.path,
                message: "Public declaration \(declarationFact.declaration.name.rawValue) is disallowed",
                location: declarationFact.declaration.location,
                evidence: ViolationEvidence(
                    observed: "public declaration \(declarationFact.declaration.name.rawValue)",
                    expectation: "disallowed public declaration matchers: \(configuration.disallowedNames.map(\.description).sorted().joined(separator: ", "))"
                )
            )
        }

        return missingRequiredNames + disallowedNames
    }

    private func storedPropertyViolations(
        file: SourceFileFacts,
        property: StoredProperty,
        graph: ArchitectureGraph,
        configuration: StoredPropertyRuleConfiguration
    ) -> [ArchitectureViolation] {
        var violations: [ArchitectureViolation] = []
        let typeName = property.type?.rawValue ?? ""

        if configuration.disallowances.contains(.storedProperty) {
            violations.append(
                violation(
                    severity: configuration.severity,
                    path: file.path,
                    message: "Stored property \(property.name.rawValue) is stored",
                    location: property.location,
                    evidence: ViolationEvidence(
                        observed: "stored property \(property.name.rawValue)",
                        expectation: "stored properties are disallowed"
                    )
                )
            )
        }

        if configuration.disallowances.contains(.storedVar), property.isMutable {
            violations.append(
                violation(
                    severity: configuration.severity,
                    path: file.path,
                    message: "Stored property \(property.name.rawValue) is mutable",
                    location: property.location,
                    evidence: ViolationEvidence(
                        observed: "mutable stored property \(property.name.rawValue)",
                        expectation: "stored vars are disallowed"
                    )
                )
            )
        }

        if configuration.disallowances.contains(.any), StringMatcher.exact("Any").matches(typeName) {
            violations.append(
                violation(
                    severity: configuration.severity,
                    path: file.path,
                    message: "Stored property \(property.name.rawValue) uses Any",
                    location: property.location,
                    evidence: ViolationEvidence(
                        observed: "stored property \(property.name.rawValue): \(typeName)",
                        expectation: "Any is disallowed in stored property types"
                    )
                )
            )
        }

        if configuration.disallowances.contains(.broadExistential), StringMatcher.prefix("any ").matches(typeName) {
            violations.append(
                violation(
                    severity: configuration.severity,
                    path: file.path,
                    message: "Stored property \(property.name.rawValue) uses a broad existential",
                    location: property.location,
                    evidence: ViolationEvidence(
                        observed: "stored property \(property.name.rawValue): \(typeName)",
                        expectation: "broad existentials are disallowed in stored property types"
                    )
                )
            )
        }

        if configuration.disallowances.contains(.rawStringIdentity),
           StringMatcher.exact("String").matches(typeName),
           isIdentifiableID(property, graph: graph) {
            violations.append(
                violation(
                    severity: configuration.severity,
                    path: file.path,
                    message: "Stored property \(property.name.rawValue) uses raw String",
                    location: property.location,
                    evidence: ViolationEvidence(
                        observed: "stored property \(property.name.rawValue): \(typeName)",
                        expectation: "Identifiable id properties must not use raw String"
                    )
                )
            )
        }

        return violations
    }

    private func isIdentifiableID(_ property: StoredProperty, graph: ArchitectureGraph) -> Bool {
        guard StringMatcher.exact("id").matches(property.name.rawValue),
              let owner = property.owner else {
            return false
        }

        return graph.sourceFiles.contains { file in
            file.nominalTypes.contains { type in
                type.name == owner && type.inheritedTypes.contains(where: isIdentifiable)
            } || file.extensionDeclarations.contains { declaration in
                declaration.extendedType == owner && declaration.inheritedTypes.contains(where: isIdentifiable)
            }
        }
    }

    private func isIdentifiable(_ type: TypeName) -> Bool {
        StringMatcher.exact("Identifiable").matches(type.rawValue)
            || StringMatcher.suffix(".Identifiable").matches(type.rawValue)
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

    private func scope(paths: [String]) -> GraphScope {
        GraphScope(paths: (try? paths.map(RelativePathPrefix.init)) ?? [])
    }

    private func firstPath(in scope: GraphScope) -> RelativeFilePath? {
        switch scope {
        case .all:
            nil
        case .paths(let paths):
            paths.sorted(by: { $0.rawValue < $1.rawValue }).first?.asFilePath
        }
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
        message: String,
        location: SourcePosition? = nil,
        evidence: ViolationEvidence? = nil
    ) -> ArchitectureViolation {
        ArchitectureViolation(
            ruleID: id,
            severity: severity,
            path: path,
            location: location,
            message: message,
            evidence: evidence
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
            return "No architecture violations found."
        }

        var lines = [
            hasErrors ? "The code breaks the architecture's rules:" : "The architecture holds, but note these warnings:",
            "",
        ]
        for violation in violations {
            lines.append(
                "- [\(violation.severity.rawValue.uppercased())] \(violation.markdownLocation): \(violation.message) (\(violation.ruleID.rawValue))"
            )
        }
        return lines.joined(separator: "\n")
    }
}

public struct ArchitectureViolation: Equatable, Sendable, Codable {
    public let ruleID: RuleID
    public let severity: Severity
    public let path: RelativeFilePath
    public let location: SourcePosition?
    public let message: String
    public let evidence: ViolationEvidence?

    public init(
        ruleID: RuleID,
        severity: Severity,
        path: RelativeFilePath,
        location: SourcePosition? = nil,
        message: String,
        evidence: ViolationEvidence? = nil
    ) {
        self.ruleID = ruleID
        self.severity = severity
        self.path = path
        self.location = location
        self.message = message
        self.evidence = evidence
    }

    public var markdownLocation: String {
        guard let location else {
            return path.rawValue
        }

        return "\(path.rawValue):\(location.line):\(location.column)"
    }
}

public struct ViolationEvidence: Equatable, Sendable, Codable {
    public let observed: String
    public let expectation: String

    public init(observed: String, expectation: String) {
        self.observed = observed
        self.expectation = expectation
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
