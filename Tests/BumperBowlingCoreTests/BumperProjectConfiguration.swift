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
                DoesNot(Declare("bumperBowling"), severity: .error)
                Requires(
                    .explicitDomainSurfaces,
                    .typedIdentity,
                    .immutableStoredState,
                    severity: .warning
                )
            }

            Component(.cli) {
                Owns("Sources/BumperBowling")
                Modules("BumperBowling")
                MayDependOn(.core)
                MayUse(.foundation)
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
