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
    /// Imports of `modules` may only occur inside the allowed scope.
    public static func importOwnership(
        _ modules: Set<StringMatcher>,
        allowed: RuleScope,
        id: RuleID = RuleID("import_ownership"),
        severity: Severity = .error
    ) -> RepositoryRule {
        RepositoryRule(
            metadata: RuleMetadata(
                id: id,
                severity: severity,
                summary: "Selected module imports stay inside their allowed owners."
            )
        ) { context in
            try context.facts(BuiltInFacts.imports).occurrences
                .filter { occurrence in
                    modules.contains { $0.matches(occurrence.module) }
                        && !allowed.includes(
                            SourceFileDescriptor(path: occurrence.path, component: occurrence.component)
                        )
                }
                .map { occurrence in
                    RuleFailure(
                        path: occurrence.path,
                        message: "\(occurrence.module.rawValue) is imported outside its allowed owners.",
                        evidence: ViolationEvidence(
                            observed: "import \(occurrence.module.rawValue) in \(occurrence.path.rawValue)",
                            expectation: "imports only inside the allowed scope"
                        )
                    )
                }
        }
    }

    /// References to `member` may only occur inside the allowed scope.
    public static func memberReferenceOwnership(
        _ member: StringMatcher,
        allowed: RuleScope,
        id: RuleID = RuleID("member_reference_ownership"),
        severity: Severity = .error
    ) -> RepositoryRule {
        RepositoryRule(
            metadata: RuleMetadata(
                id: id,
                severity: severity,
                summary: "\(member) is referenced only inside its allowed owners."
            )
        ) { context in
            try context.facts(BuiltInFacts.memberReferences)
                .filter { occurrence in
                    member.matches(occurrence.member)
                        && !allowed.includes(
                            SourceFileDescriptor(path: occurrence.path, component: occurrence.component)
                        )
                }
                .map { occurrence in
                    RuleFailure(
                        path: occurrence.path,
                        location: occurrence.location,
                        message: "\(member) is referenced outside its allowed owners.",
                        evidence: ViolationEvidence(
                            observed: occurrence.base.map { "\($0).\(occurrence.member)" } ?? occurrence.member,
                            expectation: "references only inside the allowed scope"
                        )
                    )
                }
        }
    }

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

    // ponytail: inspects aliases only; duplicate nominal currencies and
    // wrapper declarations can extend this rule without changing its contract.
    /// No typealias re-exposes `symbol` outside the allowing scope.
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

    /// Traversal of `root`'s recursive `structuralCase` belongs to its owners.
    /// Detects direct and mutual recursion over the locally-dispatched call
    /// graph when a function in the recursive group matches the configured case
    /// against an exact root-typed parameter, or against `self` in a root method.
    /// Calls on another receiver never count as recursion.
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
                .compactMap { group -> ([CallGraphFunction], CasePatternEvidence)? in
                    guard let evidence = group.compactMap({ function in
                        function.traversalEvidence(root: root, structuralCase: structuralCase)
                    }).first else {
                        return nil
                    }
                    return (group, evidence)
                }
                .flatMap { qualifiedGroup in
                    let (group, traversalEvidence) = qualifiedGroup
                    return group
                        .filter { function in
                            !owners.includes(SourceFileDescriptor(path: function.path, component: function.component))
                        }
                        .map { function in
                            RuleFailure(
                                path: function.path,
                                location: function.location,
                                message: "\(function.function.name) recursively traverses \(root.name).\(structuralCase.name) outside its owners.",
                                evidence: ViolationEvidence(
                                    observed: "recursive call group over \(root.name) matches .\(structuralCase.name) against \(traversalEvidence.subjectExpression)",
                                    expectation: "traversal implemented only by the owner scope"
                                )
                            )
                        }
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
    /// Case-pattern evidence is syntax-only. The pattern must match either an
    /// exact root-typed parameter or `self` in a function enclosed by `root`.
    func traversalEvidence(
        root: NominalSymbol,
        structuralCase: EnumCaseSymbol
    ) -> CasePatternEvidence? {
        let rootMatcher = StringMatcher.exact(root.name)
        var rootSubjects = Set(parameters.compactMap { parameter in
            rootMatcher.matches(parameter.typeSpelling) ? parameter.localName : nil
        })
        if let enclosingType, rootMatcher.matches(enclosingType.name) {
            rootSubjects.insert("self")
        }

        return casePatterns.first { evidence in
            StringMatcher.exact(structuralCase.name).matches(evidence.memberName)
                && rootSubjects.contains(evidence.subjectExpression)
        }
    }
}

private let occurrenceFallbackPath: RelativeFilePath = "Package.swift"
