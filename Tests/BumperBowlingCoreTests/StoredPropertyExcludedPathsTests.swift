import Foundation
import Testing
@testable import BumperBowlingCore

@Suite("Stored Property Excluded Paths")
struct StoredPropertyExcludedPathsTests {
    @Test
    func excludedPathsSkipTheRule() throws {
        func file(_ path: String) throws -> SourceFileFacts {
            SourceFileFacts(
                path: try RelativeFilePath(path),
                subsystem: try SubsystemID("core"),
                imports: [],
                publicDeclarations: [],
                storedProperties: [
                    StoredProperty(name: try DeclarationName("buffer"), type: try TypeName("Data"), isMutable: true),
                ]
            )
        }
        let configuration = ArchitectureConfiguration(
            subsystems: [
                SubsystemConfiguration(name: "core", modules: ["Core"], paths: ["Sources/Core"]),
            ],
            rules: RuleConfiguration(
                storedProperties: StoredPropertyRuleConfiguration(
                    severity: .error,
                    excludedPaths: ["Sources/Core/Runner.swift"],
                    disallowances: [.storedVar]
                )
            )
        )

        let report = try ArchitectureLinter(configuration: configuration)
            .lint(RepositoryFacts(files: [try file("Sources/Core/Model.swift"), try file("Sources/Core/Runner.swift")]))
        let paths = Set(report.violations.map(\.path.rawValue))

        #expect(paths.contains("Sources/Core/Model.swift"))
        #expect(!paths.contains("Sources/Core/Runner.swift"))
    }
}
