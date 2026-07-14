import Foundation
import Testing
import BumperBowlingCore
import BumperBowlingTestSupport

@Suite("Standard architectural shapers")
struct StandardShaperTests {
    @Test
    func singleDeclarationPassesForOneOwnedDeclaration() throws {
        let rule = Rules.singleDeclaration(
            symbol: NominalSymbol("AccessibilityTarget"),
            owner: try RelativePathPrefix("Sources/Plans")
        )

        let report = try RuleTestHarness(rule).evaluate(
            VirtualRepository {
                VirtualSourceFile.swift("Sources/Plans/Target.swift", component: "plans", source: "struct AccessibilityTarget {}")
            }
        )

        #expect(report.violations.isEmpty)
    }

    @Test
    func singleDeclarationFlagsDuplicatesAndForeignOwners() throws {
        let rule = Rules.singleDeclaration(
            symbol: NominalSymbol("AccessibilityTarget"),
            owner: try RelativePathPrefix("Sources/Plans")
        )

        let report = try RuleTestHarness(rule).evaluate(
            VirtualRepository {
                VirtualSourceFile.swift("Sources/Plans/Target.swift", component: "plans", source: "struct AccessibilityTarget {}")
                VirtualSourceFile.swift("Sources/Plans/Duplicate.swift", component: "plans", source: "struct AccessibilityTarget {}")
                VirtualSourceFile.swift("Sources/Score/Foreign.swift", component: "score", source: "struct AccessibilityTarget {}")
            }
        )

        #expect(report.violations.count == 2)
        #expect(report.violations.map(\.path.rawValue).sorted() == [
            "Sources/Plans/Duplicate.swift",
            "Sources/Score/Foreign.swift",
        ])
    }

    @Test
    func singleDeclarationMissingOwnerFilesIsConfigurationFailure() throws {
        let rule = Rules.singleDeclaration(
            symbol: NominalSymbol("AccessibilityTarget"),
            owner: try RelativePathPrefix("Sources/Missing")
        )

        #expect(throws: RuleEvaluationError.self) {
            _ = try RuleTestHarness(rule).evaluate(
                VirtualRepository {
                    VirtualSourceFile.swift("Sources/Plans/Target.swift", component: "plans", source: "struct AccessibilityTarget {}")
                }
            )
        }
    }

    @Test
    func constructionOwnershipFlagsOutsideBuilders() throws {
        let rule = Rules.constructionOwnership(
            symbol: NominalSymbol("InterfaceObservation"),
            allowed: .under(try RelativePathPrefix("Sources/Builders"))
        )

        let report = try RuleTestHarness(rule).evaluate(
            VirtualRepository {
                VirtualSourceFile.swift(
                    "Sources/Builders/Builder.swift",
                    component: "core",
                    source: "func make() { _ = InterfaceObservation() }"
                )
                VirtualSourceFile.swift(
                    "Sources/Feature/Rogue.swift",
                    component: "core",
                    source: "func rogue() { _ = InterfaceObservation() }"
                )
            }
        )

        #expect(report.violations.map(\.path.rawValue) == ["Sources/Feature/Rogue.swift"])
        #expect(report.violations.first?.rule.id == "construction_ownership")
    }

    @Test
    func boundaryOnlyFlagsCallsOutsideBoundary() throws {
        let rule = Rules.boundaryOnly(
            symbol: FunctionSymbol("JSONDecoder.decode"),
            allowed: .under(try RelativePathPrefix("Sources/Boundary"))
        )

        let report = try RuleTestHarness(rule).evaluate(
            VirtualRepository {
                VirtualSourceFile.swift(
                    "Sources/Boundary/Gate.swift",
                    component: "core",
                    source: "func load(data: Data) throws { _ = try JSONDecoder().decode(Thing.self, from: data) }"
                )
                VirtualSourceFile.swift(
                    "Sources/Feature/Leak.swift",
                    component: "core",
                    source: "func leak(data: Data) throws { _ = try JSONDecoder().decode(Thing.self, from: data) }"
                )
            }
        )

        #expect(report.violations.map(\.path.rawValue) == ["Sources/Feature/Leak.swift"])
    }

    @Test
    func noAlternateAliasesFlagsAliasesOutsideFacade() throws {
        let rule = Rules.noAlternateAliases(
            symbol: NominalSymbol("AccessibilityTarget"),
            allowing: .under(try RelativePathPrefix("Sources/DSL"))
        )

        let report = try RuleTestHarness(rule).evaluate(
            VirtualRepository {
                VirtualSourceFile.swift("Sources/DSL/Facade.swift", component: "core", source: "typealias Target = AccessibilityTarget")
                VirtualSourceFile.swift("Sources/Feature/Alias.swift", component: "core", source: "typealias MyTarget = AccessibilityTarget")
            }
        )

        #expect(report.violations.map(\.path.rawValue) == ["Sources/Feature/Alias.swift"])
        #expect(report.violations.first?.message.contains("MyTarget") == true)
    }

    @Test
    func canonicalTraversalFlagsRecursionOutsideOwners() throws {
        let recursiveSource = """
        func walk(hierarchy: AccessibilityHierarchy) {
            walk(hierarchy: hierarchy)
        }
        """
        let rule = Rules.canonicalTraversal(
            root: NominalSymbol("AccessibilityHierarchy"),
            structuralCase: EnumCaseSymbol("container"),
            owners: .under(try RelativePathPrefix("Sources/Traversal")),
            id: "canonical_hierarchy_traversal"
        )

        let report = try RuleTestHarness(rule).evaluate(
            VirtualRepository {
                VirtualSourceFile.swift("Sources/Traversal/Owner.swift", component: "score", source: recursiveSource)
                VirtualSourceFile.swift("Sources/Score/Invalid.swift", component: "score", source: recursiveSource)
            }
        )

        #expect(report.violations.map(\.rule.id) == ["canonical_hierarchy_traversal"])
        #expect(report.violations.map(\.path.rawValue) == ["Sources/Score/Invalid.swift"])
    }
}
