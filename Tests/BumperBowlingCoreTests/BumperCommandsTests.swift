import Foundation
import Testing
@testable import BumperBowlingCore

@Suite("BumperCommands")
struct BumperCommandsTests {
    @Test
    func scanSummarizesConfiguredRepository() async throws {
        let root = try makeRepository(source: """
        import Foundation

        public struct Thing {}
        """)

        let output = try await BumperCommands.scan(root: root)

        #expect(output.contains("Files: 1"))
        #expect(output.contains("Subsystems: core"))
        #expect(output.contains("core imports Foundation"))
    }

    @Test
    func lintReportsErrorsForFailingFixture() async throws {
        let root = try makeRepository(source: """
        import XCTest

        public struct Thing {}
        """)

        let report = try await BumperCommands.lint(root: root)

        #expect(report.hasErrors)
        #expect(report.violations.map(\.ruleID).contains(.forbiddenImport))
    }

    @Test
    func diagramIsDeterministicCommandOutput() throws {
        let root = repositoryRoot()
        let checkedInDiagram = try String(
            contentsOf: root.appendingPathComponent("SYSTEM_DIAGRAM.md"),
            encoding: .utf8
        )

        #expect(checkedInDiagram == (try BumperCommands.diagram(root: root)))
    }

    private func makeRepository(source: String) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let sourceFile = root.appendingPathComponent("Sources/BumperBowlingCore/Thing.swift")
        try FileManager.default.createDirectory(
            at: sourceFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try source.write(to: sourceFile, atomically: true, encoding: .utf8)
        return root
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
