import Foundation
import Testing
@testable import BumperBowlingCore

@Suite("Configuration Check")
struct ConfigurationCheckTests {
    @Test
    func reportsTheSampleConfigurationAsDeclarativeAndValid() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try ConfigurationLoader.writeSample(to: root)

        let report = try BumperCommands.checkConfiguration(root: root)

        #expect(report.lane == .declarative)
        #expect(report.isValid)
        #expect(report.summary.contains("The configuration is valid."))
    }

    @Test
    func reportsInvalidDeclarativeConfigurations() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = """
        import BumperBowlingCore

        let configuration = BumperConfiguration {
            Architecture {
                Component(.core) {
                    Modules("Core")
                }
            }
        }
        """
        try source.write(
            to: root.appendingPathComponent(ConfigurationLoader.fileName),
            atomically: true,
            encoding: .utf8
        )

        let report = try BumperCommands.checkConfiguration(root: root)

        #expect(report.lane == .declarative)
        #expect(!report.isValid)
        #expect(report.summary.contains("The configuration is not valid"))
        #expect(report.problem == ConfigurationError.emptySubsystemPaths("core").description)
    }

    @Test
    func reportsExecutableConfigurationsWithAReason() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = """
        import BumperBowlingCore

        private func makeConfiguration() -> BumperConfiguration {
            BumperConfiguration {
                Architecture {
                    Component(.app) {
                        Owns("Sources")
                    }
                }
            }
        }

        let configuration = makeConfiguration()
        """
        try source.write(
            to: root.appendingPathComponent(ConfigurationLoader.fileName),
            atomically: true,
            encoding: .utf8
        )

        let report = try BumperCommands.checkConfiguration(root: root)

        guard case .executable(let reason) = report.lane else {
            Issue.record("Expected the executable lane.")
            return
        }
        #expect(!reason.isEmpty)
        #expect(report.isValid)
    }
}
