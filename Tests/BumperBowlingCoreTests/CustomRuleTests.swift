import Foundation
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
}
