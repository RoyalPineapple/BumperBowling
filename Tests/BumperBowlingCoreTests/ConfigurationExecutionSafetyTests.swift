import Foundation
import Testing
@testable import BumperBowlingCore

@Suite("Configuration Execution Safety")
struct ConfigurationExecutionSafetyTests {
    /// Configurations are compiled and run to produce their value. That
    /// execution must not observe the caller's environment, must not be able
    /// to write files, and must still produce the value the config computes.
    @Test
    func executedConfigurationCannotReadEnvironmentOrWriteFiles() throws {
        setenv("BUMPER_CANARY_SECRET", "LEAKED", 1)
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let leakURL = root.appendingPathComponent("leak.txt")

        let source = """
        import BumperBowlingCore
        import Foundation

        private func makeConfiguration() -> BumperConfiguration {
            try? "leaked".write(toFile: \(leakURL.path.debugDescription), atomically: true, encoding: .utf8)
            let injected = ProcessInfo.processInfo.environment["BUMPER_CANARY_SECRET"] ?? "Sources"

            return BumperConfiguration {
                Included {
                    injected
                }

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

        let configuration = try ConfigurationLoader.loadConfiguration(root: root)

        #expect(configuration.includedPaths == ["Sources"], "environment variables must not leak into evaluation")
        #expect(
            !FileManager.default.fileExists(atPath: leakURL.path),
            "sandboxed evaluation must not be able to write files"
        )
    }
}
