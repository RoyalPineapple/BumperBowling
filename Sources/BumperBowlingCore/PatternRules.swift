import Foundation

/// A rule that forbids every match of one syntax pattern.
public struct ForbiddenPattern<Pattern: SyntaxPattern>: RuleDefinition {
    public let metadata: RuleMetadata
    public let scope: RuleScope
    private let pattern: Pattern
    private let diagnostic: @Sendable (SyntaxMatch<Pattern.Match>) -> RuleFailure

    public init(
        _ pattern: Pattern,
        metadata: RuleMetadata,
        scope: RuleScope = .repository,
        diagnostic: @escaping @Sendable (SyntaxMatch<Pattern.Match>) -> RuleFailure
    ) {
        self.pattern = pattern
        self.metadata = metadata
        self.scope = scope
        self.diagnostic = diagnostic
    }

    public func evaluate(in context: RuleContext) throws -> [RuleFailure] {
        context.files(in: scope).flatMap { file in
            pattern.matches(in: file).map(diagnostic)
        }
    }
}

/// Concrete factory so consumers never spell generic signatures.
public func forbid<Pattern: SyntaxPattern>(
    _ pattern: Pattern,
    id: RuleID,
    severity: Severity = .error,
    summary: String,
    scope: RuleScope = .repository,
    message: @escaping @Sendable (SyntaxMatch<Pattern.Match>) -> String
) -> ForbiddenPattern<Pattern> {
    ForbiddenPattern(
        pattern,
        metadata: RuleMetadata(id: id, severity: severity, summary: summary),
        scope: scope
    ) { match in
        match.failure(message: message(match))
    }
}
