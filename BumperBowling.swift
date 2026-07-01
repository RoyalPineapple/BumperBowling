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
        Layer(.core) {
            Owns("Sources/BumperBowlingCore")
            Modules("BumperBowlingCore")
            DoesNotUse("XCTest", "Testing", severity: .error)
            Requires(.explicitDomainSurfaces, .typedIdentity, .immutableState, severity: .warning)
            Requires(.enumStateMachine, severity: .error, in: "Sources/BumperBowlingCore/SwiftFileParser.swift")
        }

        Layer(.cli) {
            Owns("Sources/BumperBowling")
            Modules("BumperBowling")
            DependsOn(.core)
            DoesNotUse("XCTest", "Testing", severity: .error)
        }
    }

    Rules {
        SubsystemBoundary(.error)
        DuplicateOwnership(.error)
        DependencyCycle(.error)
    }
}
