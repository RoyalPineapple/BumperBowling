import Foundation
import SwiftSyntax

/// The rule-authoring namespace and the project's rule block. Static members
/// are prebuilt shapers and factories, implemented only through the public
/// rule, fact, and query interfaces — conveniences, not a closed taxonomy.
/// `Rules { ... }` in a `BumperProject` collects built-in shaper
/// configurations and project rule definitions into one engine.
public struct Rules: Sendable {
    let elements: [ProjectRuleElement]

    public init(@ProjectRulesBuilder _ content: () -> [ProjectRuleElement]) {
        self.elements = content()
    }
}

extension Rules {
    /// Exactly one declaration of `symbol`, owned by files under `owner`.
    /// A configured owner path with no files is a configuration failure.
    public static func singleDeclaration(
        _ symbol: NominalSymbol,
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

            let occurrences = try context.facts(BuiltInFacts.declarations).occurrences(of: symbol)

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
        _ symbol: NominalSymbol,
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
            try context.facts(BuiltInFacts.functionCalls)
                .calls(to: FunctionSymbol(symbol.name))
                .filter { call in
                    !allowed.includes(SourceFileDescriptor(path: call.path, component: call.component))
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
        function symbol: FunctionSymbol,
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
            try context.facts(BuiltInFacts.functionCalls)
                .calls(to: symbol)
                .filter { call in
                    !allowed.includes(SourceFileDescriptor(path: call.path, component: call.component))
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
        _ symbol: NominalSymbol,
        allowing: RuleScope = RuleScope { _ in false },
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
    /// Detects direct and mutual recursion over the locally-dispatched call
    /// graph; calls on another receiver never count as recursion.
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
            try context.facts(BuiltInFacts.recursiveCallGroups)
                .groups
                .filter { group in
                    group.contains { function in function.traverses(root) }
                }
                .flatMap { $0 }
                .filter { function in
                    !owners.includes(SourceFileDescriptor(path: function.path, component: function.component))
                }
                .map { function in
                    RuleFailure(
                        path: function.path,
                        location: function.location,
                        message: "\(function.function.name) recursively traverses \(root.name) outside its owners.",
                        evidence: ViolationEvidence(
                            observed: "recursive function \(function.function.name) over \(root.name)",
                            expectation: "traversal implemented only by the owner scope"
                        )
                    )
                }
        }
    }

    /// `symbol` may only be constructed by its declared owners.
    public static func canonicalConstruction(
        _ symbol: NominalSymbol,
        owners: RuleScope,
        id: RuleID = RuleID("canonical_construction"),
        severity: Severity = .error
    ) -> RepositoryRule {
        constructionOwnership(symbol, allowed: owners, id: id, severity: severity)
    }

    /// Every nominal declaration named with `suffix` lives in the owner scope.
    public static func singleNominalSpelling(
        suffix: String,
        owner: RuleScope,
        id: RuleID = RuleID("single_nominal_spelling"),
        severity: Severity = .error
    ) -> RepositoryRule {
        RepositoryRule(
            metadata: RuleMetadata(
                id: id,
                severity: severity,
                summary: "Declarations named *\(suffix) live only in their owner scope."
            )
        ) { context in
            let matcher = StringMatcher.suffix(suffix)
            return try context.facts(BuiltInFacts.nominalTypes)
                .filter { occurrence in
                    matcher.matches(occurrence.type.name)
                        && !owner.includes(SourceFileDescriptor(path: occurrence.path, component: occurrence.component))
                }
                .map { occurrence in
                    RuleFailure(
                        path: occurrence.path,
                        location: occurrence.type.location,
                        message: "\(occurrence.type.name.rawValue) is declared outside the \(suffix) owner scope.",
                        evidence: ViolationEvidence(
                            observed: "declaration of \(occurrence.type.name.rawValue)",
                            expectation: "*\(suffix) declarations only in the owner scope"
                        )
                    )
                }
        }
    }
}

private extension CallGraphFunction {
    /// The function participates in traversal of `root`: it is declared on
    /// the type or takes it as a parameter.
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

private let occurrenceFallbackPath: RelativeFilePath = "Package.swift"
