import Testing
@testable import BumperBowlingCore

@Suite("Rule Examples")
struct RuleExampleTests {
    @Test
    func forbiddenImportExamples() async throws {
        try await verifyRule(
            .forbiddenImport([RuleSetting(severity: .error, values: ["XCTest"])])
        )
    }

    @Test
    func domainModelExamples() async throws {
        try await verifyRule(
            .domainModels(
                DomainModelRuleConfiguration(
                    severity: .error,
                    paths: ["Sources/BumperBowlingCore"],
                    disallowances: [.storedVar, .rawStringIdentity]
                )
            )
        )
    }

    @Test
    func enumStateMachineExamples() async throws {
        try await verifyRule(
            .enumStateMachine(
                PathRuleConfiguration(
                    severity: .error,
                    paths: ["Sources/**/*Parser.swift"]
                )
            )
        )
    }
}
