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
