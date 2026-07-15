import Foundation

/// A rule over the whole repository context.
public struct RepositoryRule: RuleDefinition {
    public let metadata: RuleMetadata
    public let scope: RuleScope
    private let evaluateFailures: @Sendable (RuleContext) throws -> [RuleFailure]

    public init(
        metadata: RuleMetadata,
        scope: RuleScope = .repository,
        evaluate: @escaping @Sendable (RuleContext) throws -> [RuleFailure]
    ) {
        self.metadata = metadata
        self.scope = scope
        self.evaluateFailures = evaluate
    }

    public func evaluate(in context: RuleContext) throws -> [RuleFailure] {
        try evaluateFailures(context)
    }
}

extension Rules {
    /// A closure rule over the whole repository context. The required summary
    /// explains the invariant in reports and generated documentation.
    public static func repository(
        _ id: String,
        severity: Severity = .error,
        summary: String,
        scope: RuleScope = .repository,
        _ evaluate: @escaping @Sendable (RuleContext) throws -> [RuleFailure]
    ) -> RepositoryRule {
        RepositoryRule(
            metadata: RuleMetadata(id: RuleID(id), severity: severity, summary: summary),
            scope: scope,
            evaluate: evaluate
        )
    }

    /// A closure rule over each parsed source file in scope. The required
    /// summary explains the invariant in reports and generated documentation.
    public static func files(
        _ id: String,
        severity: Severity = .error,
        summary: String,
        scope: RuleScope = .repository,
        _ evaluate: @escaping @Sendable (SourceFileContext) throws -> [RuleFailure]
    ) -> SyntaxRule {
        SyntaxRule(
            metadata: RuleMetadata(id: RuleID(id), severity: severity, summary: summary),
            scope: scope,
            evaluate: evaluate
        )
    }
}

/// A rule evaluated over each parsed source file in scope.
public struct SyntaxRule: RuleDefinition {
    public let metadata: RuleMetadata
    public let scope: RuleScope
    private let evaluateFile: @Sendable (SourceFileContext) throws -> [RuleFailure]

    public init(
        metadata: RuleMetadata,
        scope: RuleScope = .repository,
        evaluate: @escaping @Sendable (SourceFileContext) throws -> [RuleFailure]
    ) {
        self.metadata = metadata
        self.scope = scope
        self.evaluateFile = evaluate
    }

    public func evaluate(in context: RuleContext) throws -> [RuleFailure] {
        try context.files(in: scope).flatMap(evaluateFile)
    }
}
