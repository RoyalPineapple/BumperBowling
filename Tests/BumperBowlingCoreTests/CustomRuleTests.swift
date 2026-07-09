import Foundation
import SwiftSyntax
import Testing
@testable import BumperBowlingCore

@Suite("Custom rules")
struct CustomRuleTests {
    @Test
    func customRuleSetEvaluatesCodableFacts() throws {
        let path = try RelativeFilePath("Sources/Core/Thing.swift")
        let input = CustomRuleInput(
            configuration: ArchitectureConfiguration(components: []),
            files: [
                CustomRuleFileFacts(
                    path: path,
                    component: "core",
                    imports: ["Foundation", "UIKit"]
                ),
            ]
        )

        let output = CustomRuleSet {
            CustomRule("custom.import_allow_list", severity: .error) { context in
                let allowedImports = Set(["Foundation"])
                return context.files.flatMap { file in
                    file.imports
                        .filter { !allowedImports.contains($0) }
                        .map { module in
                            CustomRuleFailure(
                                path: file.path,
                                message: "\(file.component) imports non-allowlisted module \(module)",
                                evidence: ViolationEvidence(
                                    observed: module,
                                    expectation: "allowed imports: Foundation"
                                )
                            )
                        }
                }
            }
        }.evaluate(input)

        let data = try JSONEncoder().encode(output)
        let roundTripped = try JSONDecoder().decode(CustomRuleOutput.self, from: data)

        #expect(roundTripped.findings.map(\.ruleID) == [RuleID("custom.import_allow_list")])
        #expect(roundTripped.findings.first?.severity == .error)
        #expect(roundTripped.findings.first?.path == path)
        #expect(roundTripped.findings.first?.evidence?.observed == "UIKit")
    }

    @Test
    func customSyntaxRuleEvaluatesRawSwiftSyntax() throws {
        let path = try RelativeFilePath("Sources/Core/Thing.swift")
        let input = CustomRuleInput(
            configuration: ArchitectureConfiguration(components: []),
            files: [
                CustomRuleFileFacts(
                    path: path,
                    component: "core",
                    source: """
                    public struct Thing {
                        public func pair() -> (String, Int) {
                            ("id", 1)
                        }
                    }
                    """,
                    imports: []
                ),
            ]
        )

        let output = CustomRuleSet {
            CustomSyntaxRule("custom.no_tuple_api", severity: .error) { file in
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
        }.evaluate(input)

        #expect(output.findings.map(\.ruleID) == [RuleID("custom.no_tuple_api")])
        #expect(output.findings.first?.path == path)
        #expect(output.findings.first?.location == SourcePosition(line: 2, column: 27))
        #expect(output.findings.first?.evidence?.observed == "(String, Int)")
    }
}

private final class TupleTypeCollector: SyntaxVisitor {
    private(set) var tuples: [TupleTypeSyntax] = []

    override func visit(_ node: TupleTypeSyntax) -> SyntaxVisitorContinueKind {
        tuples.append(node)
        return .skipChildren
    }
}
