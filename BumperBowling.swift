import BumperBowlingCore

// Bumper Bowling 0.0 exposes the Swift DSL as the typed configuration API.
// The CLI still uses its built-in config until config loading lands.
let configuration = BumperConfiguration {
    Defaults(.strict)

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
        AcyclicDependencies(.error)
    }
}
