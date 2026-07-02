import Testing
@testable import BumperBowlingCore

@Suite("BumperConfiguration DSL")
struct BumperConfigurationDSLTests {
    @Test
    func buildsTypedArchitectureConfiguration() throws {
        let configuration = BumperConfiguration {
            Included {
                "Sources"
            }

            Excluded {
                ".build"
            }

            Architecture {
                Component(.core) {
                    Owns("Sources/Core")
                    Modules("CoreKit")
                    DoesNotUse("XCTest", severity: .error)
                    Requires(.immutableStoredState, severity: .warning)
                    Disallows(.assignment, .mutableBinding, severity: .warning)
                }

                Component(.cli) {
                    Owns("Sources/CLI")
                    Modules("CLI")
                    MayDependOn(.core)
                }
            }

            Assertions {
                DependencyBoundaries(.error)
            }
        }.architectureConfiguration

        let rules = try ArchitectureRules(configuration: configuration)

        #expect(rules.includes(try RelativeFilePath("Sources/Core/Thing.swift")))
        #expect(!rules.includes(try RelativeFilePath(".build/debug/Thing.swift")))
        #expect(rules.forbiddenImports == Set([try ModuleName("XCTest")]))
        #expect(rules.ruleConfiguration.forbiddenImports.first?.paths == ["Sources/Core"])
        #expect(
            rules.ruleConfiguration.storedProperties.disallowances ==
                Set<StoredPropertyDisallowance>([.storedVar])
        )
        #expect(
            rules.ruleConfiguration.syntaxConstructs.disallowedConstructs ==
                Set<ImperativeConstruct>([.assignment, .mutableBinding])
        )
        #expect(rules.ruleConfiguration.storedProperties.paths == ["Sources/Core"])
        #expect(rules.ruleConfiguration.syntaxConstructs.paths == ["Sources/Core"])
    }

    @Test
    func exposesForbiddenComponentDependencies() throws {
        let configuration = BumperConfiguration {
            Architecture {
                Component(.core) {
                    Owns("Sources/Core")
                    DoesNotDependOn(.ui)
                }

                Component(.ui) {
                    Owns("Sources/UI")
                }
            }
        }.architectureConfiguration

        let rules = try ArchitectureRules(configuration: configuration)

        #expect(rules.subsystemByID[try SubsystemID("core")]?.forbiddenDependencies == Set([try SubsystemID("ui")]))
    }

    @Test
    func composesCustomSemanticRequirementsFromFactRules() throws {
        let valueCore = ComponentRequirement(
            .typedIdentity,
            .immutableStoredState,
            .computedState,
            .functionalCore
        )

        let configuration = BumperConfiguration {
            Architecture {
                Component(.core) {
                    Owns("Sources/Core")
                    Requires(valueCore, severity: .error)
                }
            }
        }.architectureConfiguration

        let rules = try ArchitectureRules(configuration: configuration)

        #expect(
            rules.ruleConfiguration.storedProperties.disallowances ==
                Set<StoredPropertyDisallowance>([.rawStringIdentity, .storedVar, .storedProperty])
        )
        #expect(
            rules.ruleConfiguration.syntaxConstructs.disallowedConstructs ==
                Set<ImperativeConstruct>(
                    [.assignment, .loop, .mutableBinding, .inoutExpression, .mutatingDeclaration]
                )
        )
        #expect(rules.ruleConfiguration.storedProperties.paths == ["Sources/Core"])
        #expect(rules.ruleConfiguration.syntaxConstructs.paths == ["Sources/Core"])
    }

    @Test
    func shippedSemanticRuleSetsLowerToFactRules() {
        #expect(
            ComponentRequirement.swiftBasics.factRules ==
                ComponentRequirement(
                    .explicitDomainSurfaces,
                    .typedIdentity,
                    .immutableStoredState
                ).factRules
        )
        #expect(ComponentRequirement.parserStateMachine.factRules == ComponentRequirement.enumStateMachine.factRules)
        #expect(
            ComponentRequirement.pureDomain.factRules ==
                ComponentRequirement(.swiftBasics, .functionalCore).factRules
        )
    }
}
