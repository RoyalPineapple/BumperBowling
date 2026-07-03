@testable import BumperBowlingCore

enum BumperProjectConfiguration {
    static let configuration = BumperConfiguration {
        Included {
            "Sources"
        }

        Excluded {
            ".build"
            "DerivedData"
        }

        Architecture {
            Component(.core) {
                Owns("Sources/BumperBowlingCore")
                Modules("BumperBowlingCore")
                MayUse(.foundation)
                DoesNotDependOn(.cli, .tests)
                DoesNot(Declare("bumperBowling"), severity: .error)
                Requires(DisallowSyntax(.regexLiteralExpr), severity: .error)
                Requires(.explicitDomainSurfaces, .typedIdentity, severity: .warning)
                Requires(
                    .immutableStoredState,
                    except: [
                        "Sources/BumperBowlingCore/ConfigurationCommandRunner.swift",
                        "Sources/BumperBowlingCore/SwiftFileParser.swift",
                    ],
                    severity: .error
                )
            }

            Component(.cli) {
                Owns("Sources/BumperBowling")
                Modules("BumperBowling")
                MayDependOn(.core)
                DoesNotDependOn(.tests)
                MayUse(.foundation)
                Requires(.immutableStoredState, .typedIdentity, severity: .error)
            }

            Component(.tests) {
                Owns("Sources/BumperBowlingTesting")
                Modules("BumperBowlingTesting")
                MayDependOn(.core)
                DoesNotDependOn(.cli)
                MayUse(.foundation)
                Requires(.immutableStoredState, .typedIdentity, severity: .error)
            }
        }

        Assertions {
            DependencyBoundaries(.error)
            SingleOwner(.error)
            AcyclicDeclaredDependencies(.error)
            NoDirectStringMatching(
                .error,
                paths: ["Sources/BumperBowlingCore"],
                except: ["Sources/BumperBowlingCore/StringMatcher.swift"]
            )
        }
    }.architectureConfiguration
}
