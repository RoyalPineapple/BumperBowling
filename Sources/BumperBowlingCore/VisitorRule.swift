import Foundation
import SwiftSyntax

/// A visitor that accumulates rule failures while walking one file.
public protocol RuleFailureSource: AnyObject {
    var failures: [RuleFailure] { get }
}

extension Rules {
    /// The visitor escape hatch as an authored factory. The rule owns file
    /// selection, walking, and collection; the visitor owns the analysis. The
    /// required summary explains the invariant this escape hatch protects.
    public static func visitor<Visitor: SyntaxVisitor & RuleFailureSource>(
        _ id: String,
        severity: Severity = .error,
        summary: String,
        scope: RuleScope = .repository,
        _ makeVisitor: @escaping @Sendable (SourceFileContext) -> Visitor
    ) -> VisitorRule<Visitor> {
        VisitorRule(
            metadata: RuleMetadata(id: RuleID(id), severity: severity, summary: summary),
            scope: scope,
            makeVisitor: makeVisitor
        )
    }
}

/// The permanent escape hatch: an ordinary SwiftSyntax visitor as a rule.
/// The rule owns file selection, traversal, and failure collection; the
/// visitor owns arbitrary analysis over raw SwiftSyntax.
public struct VisitorRule<Visitor>: RuleDefinition
where Visitor: SyntaxVisitor & RuleFailureSource {
    public let metadata: RuleMetadata
    public let scope: RuleScope
    private let makeVisitor: @Sendable (SourceFileContext) -> Visitor

    public init(
        metadata: RuleMetadata,
        scope: RuleScope = .repository,
        makeVisitor: @escaping @Sendable (SourceFileContext) -> Visitor
    ) {
        self.metadata = metadata
        self.scope = scope
        self.makeVisitor = makeVisitor
    }

    public func evaluate(in context: RuleContext) throws -> [RuleFailure] {
        context.files(in: scope).flatMap { file in
            let visitor = makeVisitor(file)
            visitor.walk(file.syntax)
            return visitor.failures
        }
    }
}
