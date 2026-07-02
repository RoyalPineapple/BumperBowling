import BumperBowlingCore

// Bumper Bowling exposes this Swift DSL to both shipped interfaces:
// - the CLI loads this file for shell hooks and CI jobs
// - BumperBowlingTesting uses the same configuration value in tests
let configuration = BumperConfiguration {
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
            Requires(.explicitDomainSurfaces, .typedIdentity, .immutableStoredState, severity: .warning)
            RequiresScoped(.enumStateMachine, "Sources/BumperBowlingCore/SwiftFileParser.swift", severity: .error)
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
}
