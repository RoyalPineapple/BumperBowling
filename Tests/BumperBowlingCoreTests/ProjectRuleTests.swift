import Foundation
import SwiftSyntax
import Testing
@testable import BumperBowlingCore

@Suite("Project rules")
struct ProjectRuleTests {
    @Test
    func repositoryRuleEvaluatesDerivedFacts() throws {
        let path = RelativeFilePath("Sources/Core/Thing.swift")
        let repository = RepositorySyntax(files: [
            SourceFileContext(
                descriptor: SourceFileDescriptor(path: path, component: try ComponentID("core")),
                source: """
                import Foundation
                import UIKit
                """
            ),
        ])

        let rule = Rules.repository(
            "project.import_allow_list",
            severity: .error,
            summary: "Only Foundation imports are allowed."
        ) { context in
            let allowedImports = Set(["Foundation"])
            return try context.facts(BuiltInFacts.imports).occurrences
                .filter { !allowedImports.contains($0.module.rawValue) }
                .map { occurrence in
                    RuleFailure(
                        path: occurrence.path,
                        message: "Imports non-allowlisted module \(occurrence.module.rawValue)",
                        evidence: ViolationEvidence(
                            observed: occurrence.module.rawValue,
                            expectation: "allowed imports: Foundation"
                        )
                    )
                }
        }

        let report = try RuleSet(rules: [rule]).evaluate(
            configuration: ArchitectureConfiguration(components: []),
            repository: repository
        )

        let data = try JSONEncoder().encode(report)
        let roundTripped = try JSONDecoder().decode(RuleReport.self, from: data)

        #expect(roundTripped.violations.map(\.ruleID) == [RuleID("project.import_allow_list")])
        #expect(roundTripped.violations.first?.severity == .error)
        #expect(roundTripped.violations.first?.path == path)
        #expect(roundTripped.violations.first?.evidence?.observed == "UIKit")
    }

    @Test
    func fileRuleEvaluatesRawSwiftSyntax() throws {
        let path = RelativeFilePath("Sources/Core/Thing.swift")
        let repository = RepositorySyntax(files: [
            SourceFileContext(
                descriptor: SourceFileDescriptor(path: path, component: try ComponentID("core")),
                source: """
                public struct Thing {
                    public func pair() -> (String, Int) {
                        ("id", 1)
                    }
                }
                """
            ),
        ])

        let rule = Rules.files(
            "project.no_tuple_api",
            severity: .error,
            summary: "Public tuple APIs must use named result types."
        ) { file in
            let visitor = TupleTypeCollector(viewMode: .sourceAccurate)
            visitor.walk(file.syntax)

            return visitor.tuples.map { tuple in
                file.failure(
                    at: tuple,
                    message: "Tuple API must use a named type.",
                    evidence: ViolationEvidence(
                        observed: tuple.trimmedDescription,
                        expectation: "named type"
                    )
                )
            }
        }

        let report = try RuleSet(rules: [rule]).evaluate(
            configuration: ArchitectureConfiguration(components: []),
            repository: repository
        )

        #expect(report.violations.map(\.ruleID) == [RuleID("project.no_tuple_api")])
        #expect(report.violations.first?.path == path)
        #expect(report.violations.first?.location == SourcePosition(line: 2, column: 27))
        #expect(report.violations.first?.evidence?.observed == "(String, Int)")
    }
}

private final class TupleTypeCollector: SyntaxVisitor {
    private(set) var tuples: [TupleTypeSyntax] = []

    override func visit(_ node: TupleTypeSyntax) -> SyntaxVisitorContinueKind {
        tuples.append(node)
        return .skipChildren
    }
}
