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

        let output = try await BumperCommands.scan(
            root: root,
            configuration: BumperProjectConfiguration.configuration
        )

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

        let report = try await BumperCommands.lint(
            root: root,
            configuration: BumperProjectConfiguration.configuration
        )

        #expect(report.hasErrors)
        #expect(report.violations.map(\.ruleID).contains(.forbiddenImport))
    }

    @Test
    func lintLoadsBumperBowlingSwiftConfiguration() async throws {
        let root = try makeRepository(source: """
        import Foundation

        public struct Thing {}
        """)
        try writeConfiguration(to: root)

        let report = try await BumperCommands.lint(root: root)

        #expect(!report.hasErrors)
    }

    @Test
    func changedBumperBowlingSwiftInvalidatesConfigurationRunnerCache() async throws {
        let root = try makeRepository(source: """
        import Foundation

        public struct Thing {}
        """)
        try writeConfiguration(to: root, forbiddenModule: "XCTest")

        let cleanReport = try await BumperCommands.lint(root: root)
        #expect(!cleanReport.hasErrors)

        try writeConfiguration(to: root, forbiddenModule: "Foundation")

        let failingReport = try await BumperCommands.lint(root: root)
        #expect(failingReport.hasErrors)
        #expect(failingReport.violations.contains { violation in
            violation.message.contains("Foundation")
        })
    }

    @Test
    func initWritesRunnableConfiguration() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)

        try BumperCommands.initialize(at: root)

        let report = try await BumperCommands.lint(root: root)

        #expect(!report.hasErrors)
    }

    @Test
    func architectureSnapshotIsDeterministicCommandOutput() throws {
        let root = repositoryRoot()
        let checkedInSnapshot = try String(
            contentsOf: root.appendingPathComponent("docs/ARCHITECTURE_SNAPSHOT.md"),
            encoding: .utf8
        )

        #expect(
            checkedInSnapshot == (try BumperCommands.snapshot(
                configuration: BumperProjectConfiguration.configuration
            ))
        )
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

    private func writeConfiguration(to root: URL, forbiddenModule: String = "XCTest") throws {
        let configuration = """
        import BumperBowlingCore

        let configuration = BumperConfiguration {
            Included {
                "Sources"
            }

            Excluded {
                ".build"
                "DerivedData"
            }

            Architecture {
                Component(.core) {
                    Owns("Sources/BumperBowlingCore")
                    Modules("BumperBowlingCore")
                    MayUse(.foundation)
                    DoesNotUse("\(forbiddenModule)", severity: .error)
                }
            }

            Assertions {
                SingleOwner(.error)
            }
        }
        """

        try configuration.write(
            to: root.appendingPathComponent(ConfigurationLoader.fileName),
            atomically: true,
            encoding: .utf8
        )
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
