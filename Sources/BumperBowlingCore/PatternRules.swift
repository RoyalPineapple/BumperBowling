import Foundation
import SwiftSyntax

/// A syntax pattern's allowed number of matches in one source file.
public enum SyntaxCardinality: Equatable, Sendable, CustomStringConvertible {
    case none
    case atLeast(Int)
    case atMost(Int)
    case exactly(Int)

    public var description: String {
        switch self {
        case .none:
            "no matching syntax nodes"
        case .atLeast(let count):
            "at least \(count) matching syntax node\(count == 1 ? "" : "s")"
        case .atMost(let count):
            "at most \(count) matching syntax node\(count == 1 ? "" : "s")"
        case .exactly(let count):
            "exactly \(count) matching syntax node\(count == 1 ? "" : "s")"
        }
    }
}

/// One mismatch between a syntax pattern's observed and expected cardinality.
/// The match is present when a concrete node exceeds the allowed count; it is
/// absent when the failure is an insufficient number of matches in a file.
public struct SyntaxCardinalityViolation<Node: SyntaxProtocol>: Sendable {
    public let file: SourceFileContext
    public let match: SyntaxMatch<Node>?
    public let observedCount: Int
    public let expected: SyntaxCardinality

    public func failure(message: String) -> RuleFailure {
        let evidence = ViolationEvidence(
            observed: "\(observedCount) matching syntax node\(observedCount == 1 ? "" : "s")",
            expectation: expected.description
        )

        if let match {
            return match.failure(message: message, evidence: evidence)
        }

        return RuleFailure(path: file.path, message: message, evidence: evidence)
    }
}

/// A rule that asserts a syntax pattern's cardinality in every source file in
/// scope. It reports concrete excess nodes when possible and file-level count
/// evidence when syntax is missing.
public struct CardinalityPattern<Pattern: SyntaxPattern>: RuleDefinition {
    public let metadata: RuleMetadata
    public let scope: RuleScope
    private let pattern: Pattern
    private let cardinality: SyntaxCardinality
    private let diagnostic: @Sendable (SyntaxCardinalityViolation<Pattern.Match>) -> RuleFailure

    public init(
        _ pattern: Pattern,
        cardinality: SyntaxCardinality,
        metadata: RuleMetadata,
        scope: RuleScope = .repository,
        diagnostic: @escaping @Sendable (SyntaxCardinalityViolation<Pattern.Match>) -> RuleFailure
    ) {
        self.pattern = pattern
        self.cardinality = cardinality
        self.metadata = metadata
        self.scope = scope
        self.diagnostic = diagnostic
    }

    public func evaluate(in context: RuleContext) throws -> [RuleFailure] {
        context.files(in: scope).flatMap { file in
            let matches = pattern.matches(in: file)
            return violations(for: matches, in: file).map(diagnostic)
        }
    }

    private func violations(
        for matches: [SyntaxMatch<Pattern.Match>],
        in file: SourceFileContext
    ) -> [SyntaxCardinalityViolation<Pattern.Match>] {
        let observedCount = matches.count
        let missingMatch: SyntaxCardinalityViolation<Pattern.Match> = .init(
            file: file,
            match: nil,
            observedCount: observedCount,
            expected: cardinality
        )

        switch cardinality {
        case .none:
            return matches.map { match in
                SyntaxCardinalityViolation(
                    file: file,
                    match: match,
                    observedCount: observedCount,
                    expected: cardinality
                )
            }
        case .atLeast(let minimum):
            return observedCount < minimum ? [missingMatch] : []
        case .atMost(let maximum):
            return matches.dropFirst(maximum).map { match in
                SyntaxCardinalityViolation(
                    file: file,
                    match: match,
                    observedCount: observedCount,
                    expected: cardinality
                )
            }
        case .exactly(let count):
            if observedCount < count {
                return [missingMatch]
            }

            return matches.dropFirst(count).map { match in
                SyntaxCardinalityViolation(
                    file: file,
                    match: match,
                    observedCount: observedCount,
                    expected: cardinality
                )
            }
        }
    }
}

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

extension Rules {
    /// Asserts how often a syntax pattern may occur in each source file in
    /// scope. Default diagnostics always include the observed count and the
    /// declared cardinality; excess matches retain their source location.
    public static func assert<Pattern: SyntaxPattern>(
        _ pattern: Pattern,
        cardinality: SyntaxCardinality,
        id: String,
        severity: Severity = .error,
        summary: String = "Syntax pattern cardinality is constrained.",
        scope: RuleScope = .repository,
        message: @escaping @Sendable (SyntaxCardinalityViolation<Pattern.Match>) -> String = { violation in
            "Expected \(violation.expected), found \(violation.observedCount)."
        }
    ) -> CardinalityPattern<Pattern> {
        CardinalityPattern(
            pattern,
            cardinality: cardinality,
            metadata: RuleMetadata(id: RuleID(id), severity: severity, summary: summary),
            scope: scope
        ) { violation in
            violation.failure(message: message(violation))
        }
    }

    /// Concrete factory so consumers never spell generic signatures.
    public static func forbid<Pattern: SyntaxPattern>(
        _ pattern: Pattern,
        id: String,
        severity: Severity = .error,
        summary: String = "Forbidden syntax pattern.",
        scope: RuleScope = .repository,
        message: @escaping @Sendable (SyntaxMatch<Pattern.Match>) -> String
    ) -> ForbiddenPattern<Pattern> {
        ForbiddenPattern(
            pattern,
            metadata: RuleMetadata(id: RuleID(id), severity: severity, summary: summary),
            scope: scope
        ) { match in
            match.failure(message: message(match))
        }
    }
}
