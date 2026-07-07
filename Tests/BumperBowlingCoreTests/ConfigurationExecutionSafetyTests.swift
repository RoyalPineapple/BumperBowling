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

    @Test
    func executedConfigurationCanUseConsumerOwnedShapeSources() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let consumerSourceRoot = root.appendingPathComponent(".bumper/Sources")
        try FileManager.default.createDirectory(at: consumerSourceRoot, withIntermediateDirectories: true)

        let houseStyle = """
        import BumperBowlingCore

        extension ComponentRequirement {
            static let domainHouseStyle = ComponentRequirement(
                .explicitDomainSurfaces,
                .immutableStoredState,
                .noOptionalStoredProperties
            )
        }

        let domainShape = ComponentShape {
            MayUse(.foundation)
            Requires(.domainHouseStyle, severity: .error)
        }
        """
        try houseStyle.write(
            to: consumerSourceRoot.appendingPathComponent("HouseStyle.swift"),
            atomically: true,
            encoding: .utf8
        )

        let configurationSource = """
        import BumperBowlingCore

        let configuration = BumperConfiguration {
            Architecture {
                Component(.core) {
                    Owns("Sources/Core")
                    Modules("Core")
                    Applies(domainShape)
                }
            }
        }
        """
        try configurationSource.write(
            to: root.appendingPathComponent(ConfigurationLoader.fileName),
            atomically: true,
            encoding: .utf8
        )

        let configuration = try ConfigurationLoader.loadConfiguration(root: root)
        let rules = configuration.rules

        #expect(configuration.subsystems.map(\.name) == ["core"])
        #expect(rules.storedProperties.severity == .error)
        #expect(rules.storedProperties.paths == ["Sources/Core"])
        #expect(
            rules.storedProperties.disallowances ==
                Set<StoredPropertyDisallowance>([.any, .broadExistential, .storedVar, .optionalState])
        )
    }

    @Test
    func executedConfigurationCanImportLocalRulePackage() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let packageRoot = root.appendingPathComponent(".bumper/HouseRules")
        let packageSources = packageRoot.appendingPathComponent("Sources/HouseRules")
        try FileManager.default.createDirectory(at: packageSources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".bumper"),
            withIntermediateDirectories: true
        )

        let manifest = """
        {
          "rulePackages": [
            {
              "path": ".bumper/HouseRules",
              "package": "HouseRules",
              "product": "HouseRules"
            }
          ]
        }
        """
        try manifest.write(
            to: root.appendingPathComponent(".bumper/packages.json"),
            atomically: true,
            encoding: .utf8
        )

        let packageManifest = """
        // swift-tools-version: 6.2
        import PackageDescription

        let package = Package(
            name: "HouseRules",
            platforms: [.macOS(.v15)],
            products: [
                .library(name: "HouseRules", targets: ["HouseRules"])
            ],
            dependencies: [
                .package(path: \(repositoryRoot().path.debugDescription))
            ],
            targets: [
                .target(
                    name: "HouseRules",
                    dependencies: [
                        .product(name: "BumperBowlingCore", package: "BumperBowling")
                    ]
                )
            ]
        )
        """
        try packageManifest.write(
            to: packageRoot.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )

        let rules = """
        import BumperBowlingCore

        public extension ComponentShape {
            static let importedDomain = ComponentShape {
                MayUse(.foundation)
                Requires(.noBoolStoredProperties, severity: .warning)
            }
        }
        """
        try rules.write(to: packageSources.appendingPathComponent("Rules.swift"), atomically: true, encoding: .utf8)

        let configurationSource = """
        import BumperBowlingCore
        import HouseRules

        let configuration = BumperConfiguration {
            Architecture {
                Component(.core) {
                    Owns("Sources/Core")
                    Applies(.importedDomain)
                }
            }
        }
        """
        try configurationSource.write(
            to: root.appendingPathComponent(ConfigurationLoader.fileName),
            atomically: true,
            encoding: .utf8
        )

        let configuration = try ConfigurationLoader.loadConfiguration(root: root)

        #expect(configuration.rules.storedProperties.severity == .warning)
        #expect(configuration.rules.storedProperties.disallowances == [.boolState])
    }

    @Test
    func rejectsUnsafeRulePackageManifests() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".bumper"),
            withIntermediateDirectories: true
        )
        try minimalConfiguration.write(
            to: root.appendingPathComponent(ConfigurationLoader.fileName),
            atomically: true,
            encoding: .utf8
        )

        let manifest = """
        {
          "rulePackages": [
            {
              "path": "https://example.com/Rules.git",
              "package": "Rules",
              "product": "Rules"
            }
          ]
        }
        """
        try manifest.write(
            to: root.appendingPathComponent(".bumper/packages.json"),
            atomically: true,
            encoding: .utf8
        )

        #expect(throws: BumperError.self) {
            try ConfigurationLoader.loadConfiguration(root: root)
        }
    }
}

private let minimalConfiguration = """
import BumperBowlingCore

let configuration = BumperConfiguration {
    Architecture {
        Component(.core) {
            Owns("Sources/Core")
        }
    }
}
"""

private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
