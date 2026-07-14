import Foundation
import SwiftSyntax

/// A visitor that accumulates rule failures while walking one file.
public protocol RuleViolationSource: AnyObject {
    var failures: [RuleFailure] { get }
}

/// The permanent escape hatch: an ordinary SwiftSyntax visitor as a rule.
/// The rule owns file selection, traversal, and failure collection; the
/// visitor owns arbitrary analysis over raw SwiftSyntax.
public struct VisitorRule<Visitor>: RuleDefinition
where Visitor: SyntaxVisitor & RuleViolationSource {
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
