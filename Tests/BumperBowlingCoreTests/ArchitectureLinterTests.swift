import Testing
@testable import BumperBowlingCore

@Suite("ArchitectureLinter")
struct ArchitectureLinterTests {
    @Test
    func flagsForbiddenImportsAndUndeclaredSubsystemDependencies() throws {
        let configuration = ArchitectureConfiguration(
            subsystems: [
                SubsystemConfiguration(name: "Recording", modules: ["RecordingKit"], paths: ["Sources/Recording"], mayDependOn: ["Core"]),
                SubsystemConfiguration(name: "Playback", modules: ["PlaybackKit"], paths: ["Sources/Playback"]),
                SubsystemConfiguration(name: "Core", modules: ["CoreKit"], paths: ["Sources/Core"]),
            ],
            rules: RuleConfiguration(
                forbiddenImports: RuleSetting(severity: .error, values: ["XCTest"]),
                subsystemBoundary: .error
            )
        )

        let facts = RepositoryFacts(files: [
            SourceFileFacts(
                path: try RelativeFilePath("Sources/Recording/Recorder.swift"),
                subsystem: try SubsystemID("Recording"),
                imports: [try ModuleName("CoreKit"), try ModuleName("PlaybackKit"), try ModuleName("XCTest")],
                publicDeclarations: []
            ),
        ])

        let report = try ArchitectureLinter(configuration: configuration).lint(facts)
        let messages = report.violations.map(\ArchitectureViolation.message)

        #expect(messages.contains("recording imports undeclared subsystem PlaybackKit (playback)"))
        #expect(messages.contains("recording imports forbidden module XCTest"))
    }

    @Test
    func warningSeverityDoesNotFailReport() throws {
        let file = SourceFileFacts(
            path: try RelativeFilePath("Sources/Core/Thing.swift"),
            subsystem: try SubsystemID("core"),
            imports: [try ModuleName("XCTest")],
            publicDeclarations: []
        )
        let configuration = ArchitectureConfiguration(
            subsystems: [
                SubsystemConfiguration(name: "core", modules: ["Core"], paths: ["Sources/Core"]),
            ],
            rules: RuleConfiguration(
                forbiddenImports: RuleSetting(severity: .warning, values: ["XCTest"])
            )
        )

        let report = try ArchitectureLinter(configuration: configuration)
            .lint(RepositoryFacts(files: [file]))

        #expect(report.violations.first?.severity == .warning)
        #expect(!report.hasErrors)
    }

    @Test
    func flagsDomainModelTasteViolations() throws {
        let file = SourceFileFacts(
            path: try RelativeFilePath("Sources/Core/Domain/Model.swift"),
            subsystem: try SubsystemID("core"),
            imports: [],
            publicDeclarations: [],
            storedProperties: [
                StoredProperty(name: try DeclarationName("id"), type: try TypeName("String"), isMutable: false),
                StoredProperty(name: try DeclarationName("payload"), type: try TypeName("Any"), isMutable: true),
                StoredProperty(name: try DeclarationName("service"), type: try TypeName("any Service"), isMutable: false),
            ]
        )
        let configuration = ArchitectureConfiguration(
            subsystems: [
                SubsystemConfiguration(name: "core", modules: ["Core"], paths: ["Sources/Core"]),
            ],
            rules: RuleConfiguration(
                domainModels: DomainModelRuleConfiguration(
                    severity: .error,
                    paths: ["Sources/Core/Domain"],
                    disallowances: [.any, .broadExistential, .storedVar, .rawStringIdentity]
                )
            )
        )

        let report = try ArchitectureLinter(configuration: configuration)
            .lint(RepositoryFacts(files: [file]))
        let messages = Set(report.violations.map(\.message))

        #expect(messages.contains("Stored property id uses raw String"))
        #expect(messages.contains("Stored property payload uses Any"))
        #expect(messages.contains("Stored property payload is mutable"))
        #expect(messages.contains("Stored property service uses a broad existential"))
    }

    @Test
    func flagsParserWithoutEnumStateMachine() throws {
        let file = SourceFileFacts(
            path: try RelativeFilePath("Sources/Core/FooParser.swift"),
            subsystem: try SubsystemID("core"),
            imports: [],
            publicDeclarations: [],
            enums: [try DeclarationName("Token")]
        )
        let configuration = ArchitectureConfiguration(
            subsystems: [
                SubsystemConfiguration(name: "core", modules: ["Core"], paths: ["Sources/Core"]),
            ],
            rules: RuleConfiguration(
                enumStateMachine: PathRuleConfiguration(
                    severity: .error,
                    paths: ["Sources/**/*Parser.swift"]
                )
            )
        )

        let report = try ArchitectureLinter(configuration: configuration)
            .lint(RepositoryFacts(files: [file]))

        #expect(report.violations.map(\.ruleID).contains(.enumStateMachine))
    }

    @Test
    func flagsDependencyCycle() throws {
        let configuration = ArchitectureConfiguration(
            subsystems: [
                SubsystemConfiguration(name: "core", modules: ["Core"], paths: ["Sources/Core"], mayDependOn: ["ui"]),
                SubsystemConfiguration(name: "ui", modules: ["UI"], paths: ["Sources/UI"], mayDependOn: ["core"]),
            ],
            rules: RuleConfiguration(dependencyCycle: .error)
        )

        let report = try ArchitectureLinter(configuration: configuration)
            .lint(RepositoryFacts(files: []))

        #expect(report.violations.map(\.ruleID).contains(.dependencyCycle))
    }

    @Test
    func flagsDuplicatePathOwnershipWithConfiguredSeverity() throws {
        let configuration = ArchitectureConfiguration(
            subsystems: [
                SubsystemConfiguration(name: "core", paths: ["Sources/Core"]),
                SubsystemConfiguration(name: "models", paths: ["Sources/Core/Models"]),
            ],
            rules: RuleConfiguration(duplicateOwnership: .warning)
        )

        let report = try ArchitectureLinter(configuration: configuration)
            .lint(RepositoryFacts(files: []))

        let violation = try #require(report.violations.first)
        #expect(violation.ruleID == .duplicateOwnership)
        #expect(violation.severity == .warning)
        #expect(violation.path == (try RelativeFilePath("Sources/Core/Models")))
        #expect(violation.message == "models path Sources/Core/Models overlaps core path Sources/Core")
        #expect(!report.hasErrors)
    }
}
