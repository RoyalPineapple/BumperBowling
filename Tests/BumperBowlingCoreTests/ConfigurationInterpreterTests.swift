import Foundation
import Testing
@testable import BumperBowlingCore

@Suite("Configuration Interpreter")
struct ConfigurationInterpreterTests {
    @Test
    func interpretsTheRepositoryConfigurationWithoutExecution() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent(ConfigurationLoader.fileName),
            encoding: .utf8
        )

        let interpretation = try ConfigurationInterpreter.interpret(source: source)

        #expect(interpretation == .configuration(BumperProjectConfiguration.configuration))
    }

    @Test
    func interpretedConfigurationMatchesTheTypedDSLValue() throws {
        let source = """
        import BumperBowlingCore

        let configuration = BumperConfiguration {
            Included {
                "Sources"
            }

            Architecture {
                Component(.app) {
                    Owns("Sources/App")
                    Modules("App")
                    DoesNotDependOn(.tests)
                    MayUse(.foundation, .swiftUI, severity: .warning)
                    DoesNotUse(.testing)
                    DoesNotUse("Dispatch", severity: .warning)
                    Requires(.typedIdentity, .immutableStoredState, severity: .warning)
                    RequiresScoped(.enumStateMachine, "Sources/App/Parser", severity: .note)
                    Disallows(.loop, severity: .warning, in: "Sources/App/Pure")
                    DoesNot(Declare(.prefix("legacy")), severity: .error)
                    Declares("AppMain")
                }

                Component(.core) {
                    Owns("Sources/Core")
                    MayDependOn(.app)
                }
            }

            Assertions {
                DependencyBoundaries(.error)
                SingleOwner(.error)
                AcyclicDeclaredDependencies(.error)
                NoDirectStringMatching(
                    .warning,
                    paths: ["Sources/App"],
                    except: ["Sources/App/Matchers.swift"]
                )
            }
        }
        """

        let expected = BumperConfiguration {
            Included {
                "Sources"
            }

            Architecture {
                Component(.app) {
                    Owns("Sources/App")
                    Modules("App")
                    DoesNotDependOn(.tests)
                    MayUse(.foundation, .swiftUI, severity: .warning)
                    DoesNotUse(.testing)
                    DoesNotUse("Dispatch", severity: .warning)
                    Requires(.typedIdentity, .immutableStoredState, severity: .warning)
                    RequiresScoped(.enumStateMachine, "Sources/App/Parser", severity: .note)
                    Disallows(.loop, severity: .warning, in: "Sources/App/Pure")
                    DoesNot(Declare(.prefix("legacy")), severity: .error)
                    Declares("AppMain")
                }

                Component(.core) {
                    Owns("Sources/Core")
                    MayDependOn(.app)
                }
            }

            Assertions {
                DependencyBoundaries(.error)
                SingleOwner(.error)
                AcyclicDeclaredDependencies(.error)
                NoDirectStringMatching(
                    .warning,
                    paths: ["Sources/App"],
                    except: ["Sources/App/Matchers.swift"]
                )
            }
        }.architectureConfiguration

        #expect(try ConfigurationInterpreter.interpret(source: source) == .configuration(expected))
    }

    @Test
    func interpretsTheSampleConfiguration() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try ConfigurationLoader.writeSample(to: root)
        let source = try String(
            contentsOf: root.appendingPathComponent(ConfigurationLoader.fileName),
            encoding: .utf8
        )

        guard case .configuration(let configuration) = try ConfigurationInterpreter.interpret(source: source) else {
            Issue.record("Expected the sample configuration to be interpretable.")
            return
        }

        #expect(configuration.includedPaths == ["Sources"])
        #expect(configuration.subsystems.map(\.name) == ["app"])
    }

    @Test(arguments: [
        "import Foundation\nlet configuration = BumperConfiguration { }",
        "let configuration = makeConfiguration()",
        "let answer = 42",
        "let configuration = BumperConfiguration { }\nlet other = BumperConfiguration { }",
        """
        let configuration = BumperConfiguration {
            Included {
                "Sources/\\(variant)"
            }
        }
        """,
        """
        let configuration = BumperConfiguration {
            Assertions {
                DependencyBoundaries(.fatal)
            }
        }
        """,
        """
        let configuration = BumperConfiguration {
            Architecture {
                Component(.payments) {
                    Owns("Sources/Payments")
                }
            }
        }
        """,
        """
        let configuration = BumperConfiguration {
            Architecture {
                Component(.core) {
                    Owns("Sources/Core")
                    DoesNot(ContainSyntax(.forceUnwrapExpr), severity: .error)
                }
            }
        }
        """,
    ])
    func fallsBackToExecutionOutsideTheDeclarativeSubset(source: String) throws {
        guard case .requiresExecution = try ConfigurationInterpreter.interpret(source: source) else {
            Issue.record("Expected fallback to sandboxed execution for: \(source)")
            return
        }
    }

    @Test
    func interpretationFailsOnInvalidDeclarationNames() {
        let source = """
        let configuration = BumperConfiguration {
            Architecture {
                Component(.core) {
                    Owns("Sources/Core")
                    Declares("")
                }
            }
        }
        """

        #expect(throws: ConfigurationError.emptyDeclarationName) {
            try ConfigurationInterpreter.interpret(source: source)
        }
    }
}
