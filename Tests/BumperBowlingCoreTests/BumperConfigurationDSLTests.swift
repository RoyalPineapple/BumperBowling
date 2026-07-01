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
            rules.ruleConfiguration.domainModels.disallowances ==
                Set<DomainModelDisallowance>([.storedVar, .imperativeConstructs])
        )
        #expect(
            rules.ruleConfiguration.domainModels.imperativeConstructs ==
                Set<ImperativeConstruct>([.assignment, .mutableBinding])
        )
        #expect(rules.ruleConfiguration.domainModels.paths == ["Sources/Core"])
    }
}
