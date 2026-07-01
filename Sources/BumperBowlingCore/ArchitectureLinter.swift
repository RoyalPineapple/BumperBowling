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
        let violations = registry.enabledRules.flatMap { rule in
            rule.evaluate(facts: facts, rules: rules)
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
            .dependencyCycle(configuration.dependencyCycle),
            .domainModels(configuration.domainModels),
            .enumStateMachine(configuration.enumStateMachine),
        ].filter(\.isEnabled)
    }
}

public enum ArchitectureRule: Sendable {
    case forbiddenImport(RuleSetting)
    case subsystemBoundary(Severity)
    case duplicateOwnership(Severity)
    case dependencyCycle(Severity)
    case domainModels(DomainModelRuleConfiguration)
    case enumStateMachine(PathRuleConfiguration)

    public var id: RuleID {
        switch self {
        case .forbiddenImport:
            .forbiddenImport
        case .subsystemBoundary:
            .subsystemBoundary
        case .duplicateOwnership:
            .duplicateOwnership
        case .dependencyCycle:
            .dependencyCycle
        case .domainModels:
            .domainModels
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
        case .dependencyCycle:
            "Disallows cycles in configured subsystem dependencies."
        case .domainModels:
            "Applies configured domain-model taste rules."
        case .enumStateMachine:
            "Requires parser files to declare an enum state machine."
        }
    }

    var isEnabled: Bool {
        severity != .off
    }

    private var severity: Severity {
        switch self {
        case .forbiddenImport(let setting):
            setting.severity
        case .subsystemBoundary(let severity):
            severity
        case .duplicateOwnership(let severity):
            severity
        case .dependencyCycle(let severity):
            severity
        case .domainModels(let configuration):
            configuration.severity
        case .enumStateMachine(let configuration):
            configuration.severity
        }
    }

    func evaluate(facts: RepositoryFacts, rules: ArchitectureRules) -> [ArchitectureViolation] {
        switch self {
        case .forbiddenImport(let setting):
            evaluateForbiddenImports(facts: facts, setting: setting)
        case .subsystemBoundary(let severity):
            evaluateSubsystemBoundaries(facts: facts, rules: rules, severity: severity)
        case .duplicateOwnership:
            []
        case .dependencyCycle(let severity):
            evaluateDependencyCycles(facts: facts, rules: rules, severity: severity)
        case .domainModels(let configuration):
            evaluateDomainModels(facts: facts, configuration: configuration)
        case .enumStateMachine(let configuration):
            evaluateEnumStateMachines(facts: facts, configuration: configuration)
        }
    }

    private func evaluateForbiddenImports(facts: RepositoryFacts, setting: RuleSetting) -> [ArchitectureViolation] {
        let forbiddenImports = Set((try? setting.values.map(ModuleName.init)) ?? [])

        return facts.files.flatMap { file in
            file.imports.compactMap { importedModule in
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

    private func evaluateSubsystemBoundaries(
        facts: RepositoryFacts,
        rules: ArchitectureRules,
        severity: Severity
    ) -> [ArchitectureViolation] {
        let subsystemByName = rules.subsystemByID
        var violations: [ArchitectureViolation] = []

        for file in facts.files {
            for importedModule in file.imports {
                guard let importedSubsystemName = rules.subsystemByModule[importedModule],
                      let sourceSubsystem = subsystemByName[file.subsystem]
                else {
                    continue
                }

                if sourceSubsystem.forbiddenDependencies.contains(importedSubsystemName) {
                    violations.append(
                        violation(
                            severity: severity,
                            path: file.path,
                            message: "\(file.subsystem) must not depend on \(importedModule) (\(importedSubsystemName.rawValue))"
                        )
                    )
                } else if !sourceSubsystem.allowedDependencies.contains(importedSubsystemName),
                          importedSubsystemName != file.subsystem {
                    violations.append(
                        violation(
                            severity: severity,
                            path: file.path,
                            message: "\(file.subsystem) imports undeclared subsystem \(importedModule) (\(importedSubsystemName.rawValue))"
                        )
                    )
                }
            }
        }

        return violations
    }

    private func evaluateDependencyCycles(
        facts: RepositoryFacts,
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
                let path = firstPath(for: subsystem.id, facts: facts, rules: rules)
                return [
                    violation(
                        severity: severity,
                        path: path,
                        message: "Dependency cycle includes subsystem \(subsystem.id.rawValue)"
                    ),
                ]
            }
        }

        return []
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

    private func evaluateDomainModels(
        facts: RepositoryFacts,
        configuration: DomainModelRuleConfiguration
    ) -> [ArchitectureViolation] {
        let paths = (try? configuration.paths.map(RelativePathPrefix.init)) ?? []

        return facts.files.flatMap { file in
            guard paths.isEmpty || paths.contains(where: { $0.contains(file.path) }) else {
                return [ArchitectureViolation]()
            }

            return file.storedProperties.flatMap { property in
                domainModelViolations(
                    file: file,
                    property: property,
                    configuration: configuration
                )
            }
        }
    }

    private func domainModelViolations(
        file: SourceFileFacts,
        property: StoredProperty,
        configuration: DomainModelRuleConfiguration
    ) -> [ArchitectureViolation] {
        var violations: [ArchitectureViolation] = []
        let typeName = property.type?.rawValue ?? ""

        if configuration.disallowances.contains(.storedVar), property.isMutable {
            violations.append(
                violation(
                    severity: configuration.severity,
                    path: file.path,
                    message: "Stored property \(property.name.rawValue) is mutable"
                )
            )
        }

        if configuration.disallowances.contains(.any), typeName == "Any" {
            violations.append(
                violation(
                    severity: configuration.severity,
                    path: file.path,
                    message: "Stored property \(property.name.rawValue) uses Any"
                )
            )
        }

        if configuration.disallowances.contains(.broadExistential), typeName.hasPrefix("any ") {
            violations.append(
                violation(
                    severity: configuration.severity,
                    path: file.path,
                    message: "Stored property \(property.name.rawValue) uses a broad existential"
                )
            )
        }

        if configuration.disallowances.contains(.rawStringIdentity), typeName == "String" {
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
        facts: RepositoryFacts,
        configuration: PathRuleConfiguration
    ) -> [ArchitectureViolation] {
        facts.files.compactMap { file in
            guard matchesAny(configuration.paths, file.path) else {
                return nil
            }

            guard !file.enums.contains(where: { $0.rawValue.hasSuffix("State") }) else {
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
        if pattern.contains("**/*") {
            let parts = pattern.components(separatedBy: "**/*")
            let prefix = parts.first ?? ""
            let suffix = parts.dropFirst().joined(separator: "**/*")
            return path.hasPrefix(prefix) && path.hasSuffix(suffix)
        }

        if pattern.hasSuffix("*") {
            return path.hasPrefix(String(pattern.dropLast()))
        }

        return path == pattern || path.hasPrefix(pattern + "/")
    }

    private func firstPath(
        for subsystem: SubsystemID,
        facts: RepositoryFacts,
        rules: ArchitectureRules
    ) -> RelativeFilePath {
        if let file = facts.files.first(where: { $0.subsystem == subsystem }) {
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

public struct LintReport: Equatable, Sendable {
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

public struct ArchitectureViolation: Equatable, Sendable {
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

public enum RuleID: String, Equatable, Sendable {
    case forbiddenImport = "forbidden_import"
    case subsystemBoundary = "subsystem_boundary"
    case duplicateOwnership = "duplicate_ownership"
    case dependencyCycle = "dependency_cycle"
    case domainModels = "domain_models"
    case enumStateMachine = "enum_state_machine"
}

public enum Severity: String, Equatable, Sendable {
    case off
    case note
    case warning
    case error
}
