import BumperBowlingCore

// Bumper Bowling's own architecture, asserted against itself.
// - core is the engine. It depends on nothing of ours and stays typed and boring.
// - cli and testing are thin interfaces over core. They forward; they hold no state.
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
            Applies(.bumperEngine)
        }

        Component(.cli) {
            Owns("Sources/BumperBowling")
            Modules("BumperBowling")
            Applies(.thinCommandAdapter)
        }

        Component(.tests) {
            Owns("Sources/BumperBowlingTesting")
            Modules("BumperBowlingTesting")
            Applies(.testSupportBoundary)
        }
    }

    Assertions {
        ApplyAssertions(.bumperGlobal)
    }
}
