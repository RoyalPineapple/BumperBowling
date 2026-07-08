import Foundation
import Testing
@testable import BumperBowlingCore

@Suite("Architecture Configuration Codable")
struct ArchitectureConfigurationCodableTests {
    @Test
    func richConfigurationSurvivesARoundTrip() throws {
        let configuration = ArchitectureConfiguration(
            includedPaths: ["Sources"],
            excludedPaths: [".build", "DerivedData"],
            components: [
                ComponentConfiguration(
                    name: "core",
                    modules: ["Core"],
                    paths: ["Sources/Core"],
                    mayDependOn: [],
                    mustNotDependOn: ["cli"]
                ),
                ComponentConfiguration(
                    name: "cli",
                    modules: ["CLI"],
                    paths: ["Sources/CLI"],
                    mayDependOn: ["core"]
                ),
            ],
            rules: RuleConfiguration(
                forbiddenImports: [
                    RuleSetting(severity: .error, values: ["XCTest"], paths: ["Sources/Core"]),
                ],
                componentBoundary: .error,
                duplicateOwnership: .error,
                declaredDependencyCycle: .warning,
                storedProperties: StoredPropertyRuleConfiguration(
                    severity: .warning,
                    paths: ["Sources/Core"],
                    disallowances: [.any, .storedVar, .rawStringIdentity]
                ),
                syntaxConstructs: SyntaxConstructRuleConfiguration(
                    severity: .error,
                    paths: ["Sources/Core"],
                    excludedPaths: ["Sources/Core/Matchers.swift"],
                    disallowedConstructs: [.directStringMatch, .loop]
                ),
                syntaxKinds: SyntaxKindRuleConfiguration(
                    severity: .note,
                    paths: ["Sources/Core/Parser"],
                    requiredKinds: [.enumDecl],
                    disallowedKinds: [.forceUnwrapExpr]
                ),
                syntaxNodes: SyntaxNodeRuleConfiguration(
                    severity: .warning,
                    paths: ["Sources/Core"],
                    requiredNodes: [.kind(.structDecl)],
                    disallowedNodes: [
                        SyntaxNodeMatcher(
                            kind: .attribute,
                            spelling: .exact("available")
                        )
                    ]
                ),
                publicDeclarations: PublicDeclarationRuleConfiguration(
                    severity: .error,
                    paths: ["Sources/Core"],
                    requiredNames: [.exact("CoreMain")],
                    disallowedNames: [.prefix("legacy"), .contains("Deprecated")]
                ),
                enumStateMachine: PathRuleConfiguration(severity: .warning, paths: ["Sources/Core/Parser"])
            )
        )

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(ArchitectureConfiguration.self, from: data)

        #expect(decoded == configuration)
    }

    @Test
    func decodingRejectsEmptyMatcherPatterns() throws {
        let payload = Data(#"{"mode": "prefix", "pattern": ""}"#.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(StringMatcher.self, from: payload)
        }
    }

    @Test
    func decodingRejectsEmptySyntaxKindNames() throws {
        let payload = Data(#"" ""#.utf8)

        #expect(throws: ConfigurationError.emptySyntaxKindName) {
            try JSONDecoder().decode(SyntaxKindName.self, from: payload)
        }
    }
}
