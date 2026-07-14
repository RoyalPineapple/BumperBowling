import Foundation
import SwiftSyntax

/// Prebuilt architectural shapers, implemented only through the public rule,
/// fact, and query interfaces. Conveniences, not a closed taxonomy: a
/// consumer can implement a different meaning from the lower layers.
public enum Rules {
    /// Exactly one declaration of `symbol`, owned by files under `owner`.
    /// A configured owner path with no files is a configuration failure.
    public static func singleDeclaration(
        symbol: NominalSymbol,
        owner: RelativePathPrefix,
        id: RuleID = RuleID("single_declaration"),
        severity: Severity = .error
    ) -> RepositoryRule {
        RepositoryRule(
            metadata: RuleMetadata(
                id: id,
                severity: severity,
                summary: "\(symbol.name) is declared exactly once, under \(owner.rawValue)."
            )
        ) { context in
            guard context.repository.files.contains(where: { owner.contains($0.path) }) else {
                throw RuleEvaluationError.missingConfiguredOwner(id, owner.rawValue)
            }

            let occurrences = try context.facts(DeclarationInventoryProvider.self).occurrences(of: symbol)

            guard let first = occurrences.first else {
                return [
                    RuleFailure(
                        path: owner.asFilePath ?? occurrenceFallbackPath,
                        message: "\(symbol.name) is never declared.",
                        evidence: ViolationEvidence(
                            observed: "no declaration of \(symbol.name)",
                            expectation: "one declaration under \(owner.rawValue)"
                        )
                    ),
                ]
            }

            var failures: [RuleFailure] = []
            for occurrence in occurrences where !owner.contains(occurrence.path) {
                failures.append(
                    RuleFailure(
                        path: occurrence.path,
                        location: occurrence.location,
                        message: "\(symbol.name) is declared outside its owner path.",
                        evidence: ViolationEvidence(
                            observed: "declaration of \(symbol.name) in \(occurrence.path.rawValue)",
                            expectation: "declared only under \(owner.rawValue)"
                        )
                    )
                )
            }

            for occurrence in occurrences.dropFirst() where owner.contains(occurrence.path) {
                failures.append(
                    RuleFailure(
                        path: occurrence.path,
                        location: occurrence.location,
                        message: "\(symbol.name) is declared more than once.",
                        evidence: ViolationEvidence(
                            observed: "another declaration of \(symbol.name); first is in \(first.path.rawValue)",
                            expectation: "exactly one declaration"
                        )
                    )
                )
            }

            return failures
        }
    }

    /// `symbol` may only be constructed inside the allowed scope.
    public static func constructionOwnership(
        symbol: NominalSymbol,
        allowed: RuleScope,
        id: RuleID = RuleID("construction_ownership"),
        severity: Severity = .error
    ) -> RepositoryRule {
        RepositoryRule(
            metadata: RuleMetadata(
                id: id,
                severity: severity,
                summary: "\(symbol.name) is constructed only by its allowed owners."
            )
        ) { context in
            try context.facts(FunctionCallInventoryProvider.self)
                .calls(to: FunctionSymbol(symbol.name))
                .filter { call in
                    !allowed.includes(path: call.path, component: call.component)
                }
                .map { call in
                    RuleFailure(
                        path: call.path,
                        location: call.location,
                        message: "\(symbol.name) is constructed outside its allowed owners.",
                        evidence: ViolationEvidence(
                            observed: "\(symbol.name)(...) in \(call.path.rawValue)",
                            expectation: "construction only inside the allowed scope"
                        )
                    )
                }
        }
    }

    /// Calls to `symbol` may only occur inside the allowed boundary scope.
    public static func boundaryOnly(
        symbol: FunctionSymbol,
        allowed: RuleScope,
        id: RuleID = RuleID("boundary_only_use"),
        severity: Severity = .error
    ) -> RepositoryRule {
        RepositoryRule(
            metadata: RuleMetadata(
                id: id,
                severity: severity,
                summary: "\(symbol.name) is called only at its declared boundary."
            )
        ) { context in
            try context.facts(FunctionCallInventoryProvider.self)
                .calls(to: symbol)
                .filter { call in
                    !allowed.includes(path: call.path, component: call.component)
                }
                .map { call in
                    RuleFailure(
                        path: call.path,
                        location: call.location,
                        message: "\(symbol.name) is called outside its boundary.",
                        evidence: ViolationEvidence(
                            observed: "call to \(symbol.name) in \(call.path.rawValue)",
                            expectation: "calls only inside the boundary scope"
                        )
                    )
                }
        }
    }

    /// No typealias re-exposes `symbol` outside the allowing scope.
    // ponytail: inspects aliases only; duplicate nominal currencies and
    // wrapper declarations can extend this rule without changing its contract.
    public static func noAlternateAliases(
        symbol: NominalSymbol,
        allowing: RuleScope = RuleScope { _, _ in false },
        id: RuleID = RuleID("no_alternate_aliases"),
        severity: Severity = .error
    ) -> SyntaxRule {
        SyntaxRule(
            metadata: RuleMetadata(
                id: id,
                severity: severity,
                summary: "\(symbol.name) has no alternate alias representations."
            ),
            scope: .repository
        ) { file in
            typeAliases()
                .aliasing(symbol)
                .excluding(allowing)
                .matches(in: file)
                .map { match in
                    match.failure(
                        message: "\(match.node.name.text) aliases \(symbol.name).",
                        evidence: ViolationEvidence(
                            observed: match.node.trimmedDescription,
                            expectation: "use \(symbol.name) directly"
                        )
                    )
                }
        }
    }

    /// Traversal of `root`'s recursive structure belongs to its owners.
    // ponytail: detects direct recursion over the root type; a call-graph SCC
    // provider can add mutual recursion later behind this same contract.
    public static func canonicalTraversal(
        root: NominalSymbol,
        structuralCase: EnumCaseSymbol,
        owners: RuleScope,
        id: RuleID = RuleID("canonical_traversal"),
        severity: Severity = .error
    ) -> RepositoryRule {
        RepositoryRule(
            metadata: RuleMetadata(
                id: id,
                severity: severity,
                summary: "Recursive traversal of \(root.name).\(structuralCase.name) stays with its owners."
            )
        ) { context in
            try context.facts(DirectRecursionProvider.self)
                .occurrences
                .filter { occurrence in
                    occurrence.traverses(root)
                        && !owners.includes(path: occurrence.path, component: occurrence.component)
                }
                .map { occurrence in
                    RuleFailure(
                        path: occurrence.path,
                        location: occurrence.location,
                        message: "\(occurrence.function.name) recursively traverses \(root.name) outside its owners.",
                        evidence: ViolationEvidence(
                            observed: "recursive function \(occurrence.function.name) over \(root.name)",
                            expectation: "traversal implemented only by the owner scope"
                        )
                    )
                }
        }
    }
}

private extension RecursiveFunctionOccurrence {
    func traverses(_ root: NominalSymbol) -> Bool {
        let matcher = StringMatcher.exact(root.name)
        if let enclosingType, matcher.matches(enclosingType.name) {
            return true
        }
        return parameterTypeNames.contains { name in
            matcher.matches(name)
        }
    }
}

private let occurrenceFallbackPath: RelativeFilePath = {
    guard let path = try? RelativeFilePath("Package.swift") else {
        preconditionFailure("Invalid built-in fallback path")
    }
    return path
}()
