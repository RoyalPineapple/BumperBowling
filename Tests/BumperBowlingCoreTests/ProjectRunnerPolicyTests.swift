import Foundation
import Testing
@testable import BumperBowlingCore

@Suite("Project runner policy")
struct ProjectRunnerPolicyTests {
    @Test
    func generatedPackagesUseSwiftSixWithoutRedundantUpcomingFeatures() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configurationURL = root.appendingPathComponent(ConfigurationLoader.fileName)
        try "let bumper = BumperProject(rules: [])".write(
            to: configurationURL,
            atomically: true,
            encoding: .utf8
        )
        let package = try ConfigurationLoader.makeCachedPackage(
            configurationURL: configurationURL,
            bumperPackageRoot: repositoryRoot(),
            environment: [:]
        )
        let manifest = try String(
            contentsOf: package.root.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )

        #expect(manifest.components(separatedBy: ".swiftLanguageMode(.v6)").count == 3)
        #expect(!manifest.contains("enableUpcomingFeature"))
    }

    @Test
    func cachedRunnerBuildsInReleaseConfigurationByDefault() throws {
        let configuration = try ConfigurationLoader.projectRunnerBuildConfiguration(environment: [:])
        let arguments = ConfigurationLoader.cachedRunnerBuildArguments(
            packageRoot: URL(fileURLWithPath: "/tmp/cache/abc"),
            buildConfiguration: configuration
        )

        #expect(configuration == "release")
        #expect(arguments.contains("build"))
        #expect(arguments.contains("release"))
        #expect(arguments.contains("BumperProjectRunner"))
        #expect(!arguments.contains("debug"))
    }

    @Test
    func cachedExecutablePathMatchesBuildConfiguration() {
        let executable = ConfigurationLoader.cachedRunnerExecutableURL(
            in: URL(fileURLWithPath: "/tmp/cache/abc"),
            productName: "BumperProjectRunner",
            buildConfiguration: "release"
        )

        #expect(executable.path == "/tmp/cache/abc/.build/release/BumperProjectRunner")
    }

    @Test
    func runnerBuildConfigurationHonorsSupportedOverride() throws {
        let configuration = try ConfigurationLoader.projectRunnerBuildConfiguration(
            environment: ["BUMPER_RUNNER_BUILD_CONFIGURATION": "debug"]
        )
        let arguments = ConfigurationLoader.cachedRunnerBuildArguments(
            packageRoot: URL(fileURLWithPath: "/tmp/cache/abc"),
            buildConfiguration: configuration
        )
        let executable = ConfigurationLoader.cachedRunnerExecutableURL(
            in: URL(fileURLWithPath: "/tmp/cache/abc"),
            productName: "BumperProjectRunner",
            buildConfiguration: configuration
        )

        #expect(configuration == "debug")
        #expect(arguments.contains("debug"))
        #expect(!arguments.contains("release"))
        #expect(executable.path == "/tmp/cache/abc/.build/debug/BumperProjectRunner")
    }

    @Test(arguments: ["Release", "fast", "-O", "release debug", ""])
    func runnerBuildConfigurationRejectsUnsupportedValues(rawValue: String) throws {
        // Empty trims to the default; every other unsupported value must
        // fail loudly instead of silently selecting a configuration.
        if rawValue.isEmpty {
            #expect(try ConfigurationLoader.projectRunnerBuildConfiguration(
                environment: ["BUMPER_RUNNER_BUILD_CONFIGURATION": rawValue]
            ) == "release")
            return
        }

        #expect(throws: BumperError.self) {
            _ = try ConfigurationLoader.projectRunnerBuildConfiguration(
                environment: ["BUMPER_RUNNER_BUILD_CONFIGURATION": rawValue]
            )
        }
    }

    @Test
    func overriddenBuildConfigurationChangesCacheIdentity() throws {
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

        let release = try ConfigurationLoader.makeCachedPackage(
            configurationURL: configurationURL,
            bumperPackageRoot: packageRoot,
            environment: [:]
        )
        let debug = try ConfigurationLoader.makeCachedPackage(
            configurationURL: configurationURL,
            bumperPackageRoot: packageRoot,
            environment: ["BUMPER_RUNNER_BUILD_CONFIGURATION": "debug"]
        )

        #expect(release.root.path != debug.root.path)
        #expect(release.executableURL.path.hasSuffix(".build/release/BumperProjectRunner"))
        #expect(debug.executableURL.path.hasSuffix(".build/debug/BumperProjectRunner"))
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
            bumperPackageRoot: packageRoot,
            environment: [:]
        )
        try markCachedExecutable(first, secondsAfterMetadata: 1)
        let second = try ConfigurationLoader.makeCachedPackage(
            configurationURL: configurationURL,
            bumperPackageRoot: packageRoot,
            environment: [:]
        )

        #expect(first.needsBuild)
        #expect(!second.needsBuild)
        #expect(first.root.path == second.root.path)
        #expect(first.executableURL.path == second.executableURL.path)
        #expect(second.executableURL.path.hasSuffix(".build/release/BumperProjectRunner"))
    }

    @Test
    func cachedPackageRepairsCorruptedAndStaleInputs() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configurationURL = root.appendingPathComponent(ConfigurationLoader.fileName)
        let configuration = "let bumper = 1"
        try configuration.write(to: configurationURL, atomically: true, encoding: .utf8)

        let first = try ConfigurationLoader.makeCachedPackage(
            configurationURL: configurationURL,
            bumperPackageRoot: repositoryRoot(),
            environment: [:]
        )
        try markCachedExecutable(first, secondsAfterMetadata: 1)
        let manifestURL = first.root.appendingPathComponent("Package.swift")
        let expectedManifest = try Data(contentsOf: manifestURL)
        let sources = first.root.appendingPathComponent("Sources/BumperProjectRunner")
        let copiedConfiguration = sources.appendingPathComponent("UserConfiguration.swift")
        let staleSource = sources.appendingPathComponent("Stale.swift")
        try "corrupted".write(to: manifestURL, atomically: true, encoding: .utf8)
        try "corrupted".write(to: copiedConfiguration, atomically: true, encoding: .utf8)
        try "enum Stale {}".write(to: staleSource, atomically: true, encoding: .utf8)

        let repaired = try ConfigurationLoader.makeCachedPackage(
            configurationURL: configurationURL,
            bumperPackageRoot: repositoryRoot(),
            environment: [:]
        )

        #expect(repaired.needsBuild)
        #expect(try Data(contentsOf: manifestURL) == expectedManifest)
        #expect(try String(contentsOf: copiedConfiguration, encoding: .utf8) == configuration)
        #expect(!FileManager.default.fileExists(atPath: staleSource.path))
    }

    @Test func `current metadata never hides a missing or stale executable`() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configurationURL = root.appendingPathComponent(ConfigurationLoader.fileName)
        try "let bumper = 1".write(to: configurationURL, atomically: true, encoding: .utf8)
        let packageRoot = repositoryRoot()

        let first = try ConfigurationLoader.makeCachedPackage(
            configurationURL: configurationURL,
            bumperPackageRoot: packageRoot,
            environment: [:]
        )
        let missing = try ConfigurationLoader.makeCachedPackage(
            configurationURL: configurationURL,
            bumperPackageRoot: packageRoot,
            environment: [:]
        )
        try markCachedExecutable(first, secondsAfterMetadata: -1)
        let stale = try ConfigurationLoader.makeCachedPackage(
            configurationURL: configurationURL,
            bumperPackageRoot: packageRoot,
            environment: [:]
        )

        #expect(missing.needsBuild)
        #expect(stale.needsBuild)
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

private func markCachedExecutable(_ package: CachedPackage, secondsAfterMetadata: TimeInterval) throws {
    try FileManager.default.createDirectory(
        at: package.executableURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try "#!/bin/sh\nexit 0\n".write(
        to: package.executableURL,
        atomically: true,
        encoding: .utf8
    )
    let metadataURL = package.root.appendingPathComponent(CachedPackageMetadata.fileName)
    let metadataDate = try metadataURL.resourceValues(
        forKeys: [.contentModificationDateKey]
    ).contentModificationDate ?? Date()
    try FileManager.default.setAttributes(
        [
            .modificationDate: metadataDate.addingTimeInterval(secondsAfterMetadata),
            .posixPermissions: 0o755,
        ],
        ofItemAtPath: package.executableURL.path
    )
}

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
