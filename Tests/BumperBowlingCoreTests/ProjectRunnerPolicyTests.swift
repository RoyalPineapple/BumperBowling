import Foundation
import Testing
@testable import BumperBowlingCore

@Suite("Project runner policy")
struct ProjectRunnerPolicyTests {
    @Test
    func cachedRunnerBuildsInReleaseConfiguration() {
        let arguments = ConfigurationLoader.cachedRunnerBuildArguments(
            packageRoot: URL(fileURLWithPath: "/tmp/cache/abc")
        )

        #expect(arguments.contains("build"))
        #expect(arguments.contains("release"))
        #expect(arguments.contains("BumperProjectRunner"))
        #expect(!arguments.contains("debug"))
    }

    @Test
    func cachedExecutablePathMatchesBuildConfiguration() {
        let executable = ConfigurationLoader.cachedRunnerExecutableURL(
            in: URL(fileURLWithPath: "/tmp/cache/abc"),
            productName: "BumperProjectRunner"
        )

        #expect(executable.path == "/tmp/cache/abc/.build/release/BumperProjectRunner")
    }

    @Test
    func cachedPackageIsReusedForUnchangedConfiguration() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configurationURL = root.appendingPathComponent(ConfigurationLoader.fileName)
        try "let bumper = 1".write(to: configurationURL, atomically: true, encoding: .utf8)
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let first = try ConfigurationLoader.makeCachedPackage(
            configurationURL: configurationURL,
            bumperPackageRoot: packageRoot
        )
        let second = try ConfigurationLoader.makeCachedPackage(
            configurationURL: configurationURL,
            bumperPackageRoot: packageRoot
        )

        #expect(first.needsBuild)
        #expect(!second.needsBuild)
        #expect(first.root.path == second.root.path)
        #expect(first.executableURL.path == second.executableURL.path)
        #expect(second.executableURL.path.hasSuffix(".build/release/BumperProjectRunner"))
    }

    @Test
    func evaluationTimeoutDefaultsWhenUnset() throws {
        #expect(try ConfigurationLoader.configurationEvaluationTimeout(environment: [:]) == 60)
        #expect(try ConfigurationLoader.configurationEvaluationTimeout(
            environment: ["BUMPER_EVALUATION_TIMEOUT_SECONDS": "  "]
        ) == 60)
    }

    @Test
    func evaluationTimeoutAcceptsValidOverrides() throws {
        #expect(try ConfigurationLoader.configurationEvaluationTimeout(
            environment: ["BUMPER_EVALUATION_TIMEOUT_SECONDS": "300"]
        ) == 300)
        #expect(try ConfigurationLoader.configurationEvaluationTimeout(
            environment: ["BUMPER_EVALUATION_TIMEOUT_SECONDS": "2.5"]
        ) == 2.5)
    }

    @Test(arguments: ["0", "-5", "abc", "nan", "inf", "-inf", "1e999", ""])
    func evaluationTimeoutRejectsInvalidOverrides(rawValue: String) {
        // Empty trims to the default; every other invalid form must fail
        // loudly instead of producing an unbounded or zero-length budget.
        if rawValue.isEmpty {
            #expect(throws: Never.self) {
                try ConfigurationLoader.configurationEvaluationTimeout(
                    environment: ["BUMPER_EVALUATION_TIMEOUT_SECONDS": rawValue]
                )
            }
            return
        }

        #expect(throws: BumperError.self) {
            _ = try ConfigurationLoader.configurationEvaluationTimeout(
                environment: ["BUMPER_EVALUATION_TIMEOUT_SECONDS": rawValue]
            )
        }
    }
}
