import Testing
import SwiftSyntax
@testable import BumperBowlingCore

@Suite("Syntax Node Rules")
struct SyntaxNodeRuleTests {
    @Test
    func evaluatesGenericSwiftSyntaxNodeRules() throws {
        let matcher = SyntaxNodeMatcher(kind: .attribute, spelling: .exact("available"))
        let file = SourceFileFacts(
            path: try RelativeFilePath("Sources/Core/Thing.swift"),
            component: try ComponentID("core"),
            imports: [],
            publicDeclarations: [],
            syntaxNodes: SwiftSyntaxNodeCatalog(
                nodes: [
                    ObservedSyntaxNode(
                        kind: .attribute,
                        spelling: "available",
                        location: SourcePosition(line: 1, column: 2),
                        parentKind: .attributeList,
                        ancestorKinds: [.structDecl]
                    )
                ]
            )
        )
        let configuration = ArchitectureConfiguration(
            components: [
                ComponentConfiguration(name: "core", modules: ["Core"], paths: ["Sources/Core"])
            ],
            rules: RuleConfiguration(
                syntaxNodes: SyntaxNodeRuleConfiguration(
                    severity: .error,
                    paths: ["Sources/Core"],
                    requiredNodes: [.kind(.structDecl)],
                    disallowedNodes: [matcher]
                )
            )
        )

        let report = try ArchitectureLinter(configuration: configuration)
            .lint(RepositoryFacts(files: [file]))
        let messages = Set(report.violations.map(\.message))

        #expect(report.violations.allSatisfy { $0.ruleID == .syntaxNodes })
        #expect(messages.contains("Missing required SwiftSyntax node kind=structDecl"))
        #expect(messages.contains("Uses disallowed SwiftSyntax node attribute available"))
        #expect(report.violations.compactMap(\.location).contains(SourcePosition(line: 1, column: 2)))
    }
}
