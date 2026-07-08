import Testing
@testable import BumperBowlingCore

@Suite("ArchitectureRules")
struct ArchitectureRulesTests {
    @Test
    func rejectsUnknownDependencies() {
        let configuration = ArchitectureConfiguration(
            components: [
                ComponentConfiguration(
                    name: "Recording",
                    paths: ["Sources/Recording"],
                    mayDependOn: ["Playback"]
                ),
            ]
        )

        #expect(throws: ConfigurationError.unknownDependency("recording", "playback")) {
            try ArchitectureRules(configuration: configuration)
        }
    }

    @Test
    func rejectsDuplicateModuleAliases() {
        let configuration = ArchitectureConfiguration(
            components: [
                ComponentConfiguration(name: "Recording", modules: ["FeatureKit"], paths: ["Sources/Recording"]),
                ComponentConfiguration(name: "Playback", modules: ["FeatureKit"], paths: ["Sources/Playback"]),
            ]
        )

        #expect(throws: ConfigurationError.duplicateModule("FeatureKit")) {
            try ArchitectureRules(configuration: configuration)
        }
    }

    @Test
    func recordsOverlappingPathOwnership() throws {
        let configuration = ArchitectureConfiguration(
            components: [
                ComponentConfiguration(name: "Core", paths: ["Sources/Core"]),
                ComponentConfiguration(name: "Models", paths: ["Sources/Core/Models"]),
            ]
        )

        let rules = try ArchitectureRules(configuration: configuration)
        let conflict = try #require(rules.pathOwnershipConflicts.first)

        #expect(conflict.path == (try RelativePathPrefix("Sources/Core/Models")))
        #expect(conflict.owner == (try ComponentID("Models")))
        #expect(conflict.overlappingPath == (try RelativePathPrefix("Sources/Core")))
        #expect(conflict.overlappingOwner == (try ComponentID("Core")))
    }

    @Test
    func rejectsAbsoluteConfiguredPaths() {
        let configuration = ArchitectureConfiguration(
            includedPaths: ["/Sources"],
            components: [
                ComponentConfiguration(name: "Core", paths: ["Sources/Core"]),
            ]
        )

        #expect(throws: ConfigurationError.unsafePath("/Sources")) {
            try ArchitectureRules(configuration: configuration)
        }
    }

    @Test
    func rejectsTraversalInRulePaths() {
        let configuration = ArchitectureConfiguration(
            components: [
                ComponentConfiguration(name: "Core", paths: ["Sources/Core"]),
            ],
            rules: RuleConfiguration(
                storedProperties: StoredPropertyRuleConfiguration(
                    severity: .error,
                    paths: ["../Secrets"],
                    disallowances: [.any]
                )
            )
        )

        #expect(throws: ConfigurationError.unsafePath("../Secrets")) {
            try ArchitectureRules(configuration: configuration)
        }
    }
}
