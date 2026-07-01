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

            Subsystems {
                Subsystem(.core) {
                    Paths("Sources/Core")
                    Modules("CoreKit")
                }

                Subsystem(.cli) {
                    Paths("Sources/CLI")
                    Modules("CLI")
                    Dependencies(.core)
                }
            }

            Rules {
                ForbiddenImport(.error) {
                    Modules("XCTest")
                }

                DomainModels(.warning) {
                    Paths("Sources/Core")
                    Disallow(.storedVar)
                }
            }
        }.architectureConfiguration

        let rules = try ArchitectureRules(configuration: configuration)

        #expect(rules.includes(try RelativeFilePath("Sources/Core/Thing.swift")))
        #expect(!rules.includes(try RelativeFilePath(".build/debug/Thing.swift")))
        #expect(rules.forbiddenImports == Set([try ModuleName("XCTest")]))
        #expect(rules.ruleConfiguration.domainModels.disallowances == [.storedVar])
    }
}
