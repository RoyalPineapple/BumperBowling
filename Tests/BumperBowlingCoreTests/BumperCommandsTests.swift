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
    func architectureSnapshotIsDeterministicCommandOutput() throws {
        let root = repositoryRoot()
        let checkedInSnapshot = try String(
            contentsOf: root.appendingPathComponent("docs/ARCHITECTURE_SNAPSHOT.md"),
            encoding: .utf8
        )

        #expect(checkedInSnapshot == (try BumperCommands.snapshot(root: root)))
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
