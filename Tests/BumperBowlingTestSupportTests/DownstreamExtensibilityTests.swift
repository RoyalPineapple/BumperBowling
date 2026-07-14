import Foundation
import SwiftSyntax
import Testing
import BumperBowlingCore
import BumperBowlingTestSupport

/// A downstream fixture: everything here uses only public API, no
/// `@testable import`, no checkout, no Bumper source edits.
@Suite("Downstream extensibility")
struct DownstreamExtensibilityTests {
    @Test
    func downstreamVisitorRuleRunsAloneWithStructuredEvidence() throws {
        let rule = VisitorRule(
            metadata: RuleMetadata(
                id: "project.no_force_unwrap",
                severity: .error,
                summary: "Production code never force-unwraps."
            ),
            scope: .productionSources
        ) { file in
            ForceUnwrapVisitor(file: file)
        }

        let report = try RuleTestHarness(rule).evaluate(
            VirtualRepository {
                VirtualSourceFile.swift(
                    "Sources/App/Feature.swift",
                    component: "app",
                    source: "func f(value: Int?) -> Int { value! }"
                )
                VirtualSourceFile.swift(
                    "Tests/AppTests/FeatureTests.swift",
                    component: "app",
                    source: "func t(value: Int?) -> Int { value! }"
                )
            }
        )

        let violation = try #require(report.violations.first)
        #expect(report.violations.count == 1)
        #expect(violation.rule.id == RuleID("project.no_force_unwrap"))
        #expect(violation.path.rawValue == "Sources/App/Feature.swift")
        #expect(violation.location != nil)
        #expect(violation.evidence == ViolationEvidence(observed: "value!", expectation: "no force unwrap"))
    }

    @Test
    func downstreamFactProvidersDeriveOnceAndCompose() throws {
        let rule = RepositoryRule(
            metadata: RuleMetadata(
                id: "project.view_naming",
                severity: .error,
                summary: "Views end in View."
            )
        ) { context in
            try context.facts(MisnamedViewProvider.self).map { occurrence in
                RuleFailure(
                    path: occurrence.path,
                    location: occurrence.location,
                    message: "\(occurrence.symbol.name) looks like a view but is not named one."
                )
            }
        }

        let report = try RuleTestHarness(rule).evaluate(
            VirtualRepository {
                VirtualSourceFile.swift("Sources/App/GoodView.swift", component: "app", source: "struct GoodView {}")
                VirtualSourceFile.swift("Sources/App/BadScreen.swift", component: "app", source: "struct BadScreen {}")
            }
        )

        #expect(report.violations.map(\.message) == ["BadScreen looks like a view but is not named one."])
    }

    @Test
    func downstreamQueryExtensionComposesWithBuiltInQueries() throws {
        let rule = forbid(
            functions().asyncFunctions().within(.productionSources),
            id: "project.no_async",
            summary: "This layer stays synchronous."
        ) { match in
            "\(match.node.name.text) is async."
        }

        let report = try RuleTestHarness(rule).evaluate(
            VirtualRepository {
                VirtualSourceFile.swift(
                    "Sources/App/Sync.swift",
                    component: "app",
                    source: """
                    func plain() {}
                    func fetch() async {}
                    """
                )
            }
        )

        #expect(report.violations.map(\.message) == ["fetch is async."])
    }

    @Test
    func downstreamRuleGroupsEnterOneRuleSet() throws {
        let rules = RuleSet {
            projectRules()
            forbid(functionCalls(), id: "extra", summary: "none") { _ in "call" }
        }

        #expect(rules.rules.map(\.metadata.id) == [
            RuleID("project.first"),
            RuleID("project.second"),
            RuleID("extra"),
        ])
    }

    @Test
    func harnessReturnsCanonicalReportForConsumption() throws {
        let rule = CustomRule("project.no_uikit") { context in
            context.files.flatMap { file in
                file.imports
                    .filter { $0 == "UIKit" }
                    .map { _ in
                        RuleFailure(path: file.path, message: "UIKit is not allowed here.")
                    }
            }
        }

        let report = try RuleTestHarness(rule).evaluate(
            VirtualRepository {
                VirtualSourceFile.swift("Sources/App/Screen.swift", component: "app", source: "import UIKit")
            }
        )

        let encoded = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(RuleReport.self, from: encoded)
        #expect(decoded == report)
        #expect(decoded.violations.map(\.rule.id) == [RuleID("project.no_uikit")])
    }
}

private func projectRules() -> [AnyRuleDefinition] {
    RuleSet {
        CustomRule("project.first") { _ in [] }
        CustomRule("project.second") { _ in [] }
    }.rules
}

// A downstream-defined provider depending on another downstream provider.
private struct ViewLikeTypesProvider: FactProvider {
    static let id: FactProviderID = "project.view_like_types"

    func derive(in context: FactDerivationContext) throws -> [DeclarationOccurrence] {
        try context.facts(DeclarationInventoryProvider.self).occurrences.filter { occurrence in
            occurrence.kind == .struct
        }
    }
}

private struct MisnamedViewProvider: FactProvider {
    static let id: FactProviderID = "project.misnamed_views"

    func derive(in context: FactDerivationContext) throws -> [DeclarationOccurrence] {
        try context.facts(ViewLikeTypesProvider.self).filter { occurrence in
            !occurrence.symbol.name.hasSuffix("View")
        }
    }
}

// A downstream query extension over a built-in query root.
private extension SyntaxQuery where Node == FunctionDeclSyntax {
    func asyncFunctions() -> Self {
        filter { match in
            match.node.signature.effectSpecifiers?.asyncSpecifier != nil
        }
    }
}

private final class ForceUnwrapVisitor: SyntaxVisitor, RuleViolationSource {
    private let file: SourceFileContext
    private(set) var failures: [RuleFailure] = []

    init(file: SourceFileContext) {
        self.file = file
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ForceUnwrapExprSyntax) -> SyntaxVisitorContinueKind {
        failures.append(
            file.failure(
                at: node,
                message: "Force unwrap is not allowed in production sources.",
                evidence: ViolationEvidence(observed: node.trimmedDescription, expectation: "no force unwrap")
            )
        )
        return .visitChildren
    }
}
