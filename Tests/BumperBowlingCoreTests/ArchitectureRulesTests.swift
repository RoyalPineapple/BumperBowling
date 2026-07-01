import Testing
@testable import BumperBowlingCore

@Suite("ArchitectureRules")
struct ArchitectureRulesTests {
    @Test
    func rejectsUnknownDependencies() {
        let configuration = ArchitectureConfiguration(
            subsystems: [
                SubsystemConfiguration(
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
            subsystems: [
                SubsystemConfiguration(name: "Recording", modules: ["FeatureKit"], paths: ["Sources/Recording"]),
                SubsystemConfiguration(name: "Playback", modules: ["FeatureKit"], paths: ["Sources/Playback"]),
            ]
        )

        #expect(throws: ConfigurationError.duplicateModule("FeatureKit")) {
            try ArchitectureRules(configuration: configuration)
        }
    }
}
