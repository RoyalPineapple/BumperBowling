import BumperBowlingCore

let configuration = BumperConfiguration {
    Defaults(.strict)

    Included {
        "Sources"
    }

    Excluded {
        ".build"
        "DerivedData"
    }

    Subsystems {
        Subsystem(.core) {
            Paths("Sources/BumperBowlingCore")
            Modules("BumperBowlingCore")
        }

        Subsystem(.cli) {
            Paths("Sources/BumperBowling")
            Modules("BumperBowling")
            Dependencies(.core)
        }
    }

    Rules {
        ForbiddenImport(.error) {
            Modules("XCTest", "Testing")
            AppliesTo(.production)
        }

        SubsystemBoundary(.error)
        DuplicateOwnership(.error)
        DependencyCycle(.error)

        DomainModels(.warning) {
            Paths("Sources/BumperBowlingCore")
            Disallow(.any)
            Disallow(.broadExistential)
            Disallow(.storedVar)
            Disallow(.rawStringIdentity)
        }
    }

    OptInRules {
        EnumStateMachine(.error) {
            Paths("Sources/**/*Parser.swift")
        }
    }
}
