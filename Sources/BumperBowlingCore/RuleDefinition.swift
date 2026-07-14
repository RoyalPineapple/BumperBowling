import Foundation

/// Identity, severity, and invariant summary for one rule.
/// `summary` describes the invariant; it is not the violation message.
public struct RuleMetadata: Equatable, Sendable, Codable {
    public let id: RuleID
    public let severity: Severity
    public let summary: String

    public init(id: RuleID, severity: Severity, summary: String) {
        self.id = id
        self.severity = severity
        self.summary = summary
    }
}

/// One diagnostic produced by rule evaluation, before rule metadata attaches.
public struct RuleFailure: Equatable, Sendable {
    public let path: RelativeFilePath
    public let location: SourcePosition?
    public let message: String
    public let evidence: ViolationEvidence?

    public init(
        path: RelativeFilePath,
        location: SourcePosition? = nil,
        message: String,
        evidence: ViolationEvidence? = nil
    ) {
        self.path = path
        self.location = location
        self.message = message
        self.evidence = evidence
    }
}

/// The canonical structured diagnostic. Evaluation, tests, CLI, JSON, and
/// Markdown all project this one value.
public struct RuleViolation: Equatable, Sendable, Codable {
    public let rule: RuleMetadata
    public let path: RelativeFilePath
    public let location: SourcePosition?
    public let message: String
    public let evidence: ViolationEvidence?

    public init(
        rule: RuleMetadata,
        path: RelativeFilePath,
        location: SourcePosition? = nil,
        message: String,
        evidence: ViolationEvidence? = nil
    ) {
        self.rule = rule
        self.path = path
        self.location = location
        self.message = message
        self.evidence = evidence
    }

    public init(rule: RuleMetadata, failure: RuleFailure) {
        self.init(
            rule: rule,
            path: failure.path,
            location: failure.location,
            message: failure.message,
            evidence: failure.evidence
        )
    }
}

/// The canonical structured report over one evaluation.
public struct RuleReport: Equatable, Sendable, Codable {
    public let violations: [RuleViolation]

    public init(violations: [RuleViolation]) {
        self.violations = violations
    }

    public var hasErrors: Bool {
        violations.contains { violation in
            violation.rule.severity == .error
        }
    }
}

/// One rule: identity, scope, and evaluation over an immutable context.
/// Built-in and consumer rules conform to this same protocol.
public protocol RuleDefinition: Sendable {
    var metadata: RuleMetadata { get }
    var scope: RuleScope { get }

    func evaluate(in context: RuleContext) throws -> [RuleFailure]
}

/// Type erasure at the heterogeneous collection boundary only.
public struct AnyRuleDefinition: RuleDefinition {
    public let metadata: RuleMetadata
    public let scope: RuleScope
    private let evaluateInContext: @Sendable (RuleContext) throws -> [RuleFailure]

    public init(_ rule: some RuleDefinition) {
        if let erased = rule as? AnyRuleDefinition {
            self = erased
            return
        }
        self.metadata = rule.metadata
        self.scope = rule.scope
        self.evaluateInContext = rule.evaluate(in:)
    }

    public func evaluate(in context: RuleContext) throws -> [RuleFailure] {
        try evaluateInContext(context)
    }
}

@resultBuilder
public enum RuleSetBuilder {
    public static func buildExpression(_ expression: some RuleDefinition) -> [AnyRuleDefinition] {
        [AnyRuleDefinition(expression)]
    }

    public static func buildExpression(_ expression: [AnyRuleDefinition]) -> [AnyRuleDefinition] {
        expression
    }

    public static func buildBlock(_ components: [AnyRuleDefinition]...) -> [AnyRuleDefinition] {
        components.flatMap { $0 }
    }

    public static func buildOptional(_ component: [AnyRuleDefinition]?) -> [AnyRuleDefinition] {
        component ?? []
    }

    public static func buildEither(first component: [AnyRuleDefinition]) -> [AnyRuleDefinition] {
        component
    }

    public static func buildEither(second component: [AnyRuleDefinition]) -> [AnyRuleDefinition] {
        component
    }

    public static func buildArray(_ components: [[AnyRuleDefinition]]) -> [AnyRuleDefinition] {
        components.flatMap { $0 }
    }
}

/// One heterogeneous rule collection evaluated by one engine.
public struct RuleSet: Sendable {
    public let rules: [AnyRuleDefinition]

    public init(rules: [AnyRuleDefinition]) {
        self.rules = rules
    }

    public init(@RuleSetBuilder _ rules: () -> [AnyRuleDefinition]) {
        self.init(rules: rules())
    }

    public static let empty = RuleSet(rules: [])

    /// Evaluates every rule over the shared context. Analysis errors are not
    /// violations: a throwing rule aborts the run with an explicit error.
    public func evaluate(in context: RuleContext) throws -> RuleReport {
        let collected = try rules.flatMap { rule in
            try Self.violations(of: rule, in: context)
        }
        return RuleReport(violations: collected.deterministicallySorted())
    }

    public func evaluateConcurrently(
        in context: RuleContext,
        maxConcurrentRuleJobs: Int? = nil
    ) async throws -> RuleReport {
        let results = await concurrentMap(
            rules,
            maxConcurrentJobs: maxConcurrentRuleJobs
        ) { rule in
            Result { try Self.violations(of: rule, in: context) }
        }

        let collected = try results.flatMap { result in
            try result.get()
        }
        return RuleReport(violations: collected.deterministicallySorted())
    }

    private static func violations(of rule: AnyRuleDefinition, in context: RuleContext) throws -> [RuleViolation] {
        do {
            return try rule.evaluate(in: context).map { failure in
                RuleViolation(rule: rule.metadata, failure: failure)
            }
        } catch let error as RuleEvaluationError {
            throw error
        } catch {
            throw RuleEvaluationError.ruleFailed(rule.metadata.id, String(describing: error))
        }
    }
}

/// Explicit analysis failures. Never converted into empty match sets.
public enum RuleEvaluationError: Error, Equatable, Sendable, CustomStringConvertible {
    case ruleFailed(RuleID, String)
    case missingSource(RelativeFilePath)
    case missingConfiguredOwner(RuleID, String)

    public var description: String {
        switch self {
        case .ruleFailed(let id, let message):
            "Rule \(id.rawValue) failed to evaluate: \(message)"
        case .missingSource(let path):
            "Source text is unavailable for \(path.rawValue); rules over syntax cannot evaluate."
        case .missingConfiguredOwner(let id, let owner):
            "Rule \(id.rawValue) requires configured owner files under \(owner), but none exist."
        }
    }
}
