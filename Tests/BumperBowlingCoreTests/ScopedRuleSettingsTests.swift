import Testing
@testable import BumperBowlingCore

@Suite("Scoped Rule Settings")
struct ScopedRuleSettingsTests {
    @Test
    func evaluatesComposedStoredPropertyRequirementsAsScopedSettings() throws {
        let file = SourceFileFacts(
            path: RelativeFilePath("Sources/Core/Runtime/Session.swift"),
            component: try ComponentID("core"),
            imports: [],
            publicDeclarations: [],
            storedProperties: [
                StoredProperty(name: try DeclarationName("payload"), type: try TypeName("Any"), isMutable: false),
                StoredProperty(name: try DeclarationName("failure"), type: try TypeName("Failure?"), isMutable: false),
                StoredProperty(name: try DeclarationName("isReady"), type: try TypeName("Bool"), isMutable: false)
            ]
        )
        let shape = ComponentShape {
            Requires(.explicitDomainSurfaces, severity: .error)
            Requires(.noOptionalStoredProperties, .noBoolStoredProperties, severity: .warning)
        }
        let configuration = BumperProject {
            Architecture {
                Component(.core) {
                    Owns("Sources/Core")
                    Applies(shape)
                }
            }
        }.architecture

        let report = try ArchitectureLinter(configuration: configuration)
            .lint(RepositoryFacts(files: [file]))
        let findings = Dictionary(uniqueKeysWithValues: report.violations.map { ($0.message, $0.severity) })

        #expect(findings["Stored property payload uses Any"] == .error)
        #expect(findings["Stored property failure uses optional state"] == .warning)
        #expect(findings["Stored property isReady uses Bool state"] == .warning)
    }

    @Test
    func preservesScopedRequirementSettingsWhenShapesCompose() throws {
        let domainShape = ComponentShape {
            Requires(.explicitDomainSurfaces, severity: .error)
            Requires(.noOptionalStoredProperties, .noBoolStoredProperties, severity: .warning)
        }

        let configuration = BumperProject {
            Architecture {
                Component(.core) {
                    Owns("Sources/Core")
                    Applies(domainShape)
                }
            }
        }.architecture

        let rules = try ArchitectureRules(configuration: configuration)

        #expect(rules.ruleConfiguration.storedProperties.severity == .error)
        #expect(
            rules.ruleConfiguration.storedProperties.disallowances ==
                Set<StoredPropertyDisallowance>([
                    .any,
                    .broadExistential,
                    .optionalState,
                    .boolState
                ])
        )
        #expect(rules.ruleConfiguration.storedPropertyRules.count == 3)
        #expect(rules.ruleConfiguration.storedPropertyRules[0].severity == .error)
        #expect(rules.ruleConfiguration.storedPropertyRules[0].disallowances == [.any, .broadExistential])
        #expect(rules.ruleConfiguration.storedPropertyRules[1].severity == .warning)
        #expect(rules.ruleConfiguration.storedPropertyRules[1].disallowances == [.optionalState])
        #expect(rules.ruleConfiguration.storedPropertyRules[2].severity == .warning)
        #expect(rules.ruleConfiguration.storedPropertyRules[2].disallowances == [.boolState])
    }
}
