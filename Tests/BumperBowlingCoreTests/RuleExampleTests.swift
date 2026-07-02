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
    func storedPropertyExamples() async throws {
        try await verifyRule(
            .storedProperties(
                StoredPropertyRuleConfiguration(
                    severity: .error,
                    paths: ["Sources/BumperBowlingCore"],
                    disallowances: [.storedVar, .rawStringIdentity]
                )
            )
        )
    }

    @Test
    func syntaxConstructExamples() async throws {
        try await verifyRule(
            .syntaxConstructs(
                SyntaxConstructRuleConfiguration(
                    severity: .error,
                    paths: ["Sources/BumperBowlingCore"],
                    disallowedConstructs: [.assignment, .mutableBinding]
                )
            )
        )
    }

    @Test
    func publicDeclarationExamples() async throws {
        try await verifyRule(
            .publicDeclarations(
                PublicDeclarationRuleConfiguration(
                    severity: .error,
                    paths: ["Sources/BumperBowlingCore"],
                    disallowedNames: [.exact("bumperBowling")]
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
