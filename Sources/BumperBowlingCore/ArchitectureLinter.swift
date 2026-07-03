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

}

extension RelativePathPrefix {
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
