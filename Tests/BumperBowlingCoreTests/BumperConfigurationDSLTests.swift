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
                Layer(.core) {
                    Owns("Sources/Core")
                    Modules("CoreKit")
                    DoesNotUse("XCTest", severity: .error)
                    Requires(.immutableState, .functionalCore, severity: .warning)
                }

                Layer(.cli) {
                    Owns("Sources/CLI")
                    Modules("CLI")
                    DependsOn(.core)
                }
            }

            Rules {
                SubsystemBoundary(.error)
            }
        }.architectureConfiguration

        let rules = try ArchitectureRules(configuration: configuration)

        #expect(rules.includes(try RelativeFilePath("Sources/Core/Thing.swift")))
        #expect(!rules.includes(try RelativeFilePath(".build/debug/Thing.swift")))
        #expect(rules.forbiddenImports == Set([try ModuleName("XCTest")]))
        #expect(rules.ruleConfiguration.forbiddenImports.first?.paths == ["Sources/Core"])
        #expect(rules.ruleConfiguration.domainModels.disallowances == [.storedVar, .imperativeConstructs])
        #expect(rules.ruleConfiguration.domainModels.paths == ["Sources/Core"])
    }
}
