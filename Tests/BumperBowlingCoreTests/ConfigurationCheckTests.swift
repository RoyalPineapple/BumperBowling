import Foundation
import Testing
@testable import BumperBowlingCore

@Suite("Configuration Check")
struct ConfigurationCheckTests {
    @Test
    func reportsTheSampleConfigurationAsValid() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try ConfigurationLoader.writeSample(to: root)

        let report = try BumperCommands.checkConfiguration(root: root)

        #expect(report.isValid)
        #expect(report.summary.contains("The configuration is valid."))
    }

    @Test
    func reportsInvalidConfigurations() throws {
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

        #expect(!report.isValid)
        #expect(report.summary.contains("The configuration is not valid"))
        #expect(report.problem == ConfigurationError.emptyComponentPaths("core").description)
    }
}
