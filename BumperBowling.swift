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
            MayUse(.foundation)
            DoesNotDependOn(.cli, .tests)
            DoesNot(Declare("bumperBowling"), severity: .error)
            // ponytail: catches `/.../` regex literals only; NSRegularExpression/Regex(...)
            // are plain calls SwiftSyntax can't tell from any other. SwiftSyntax-first is the rule.
            Requires(DisallowSyntax(.regexLiteralExpr), severity: .error)
            Requires(.explicitDomainSurfaces, .typedIdentity, severity: .warning)
            // Immutable stored state, except the two sites that legitimately hold it:
            // the lock-guarded output buffer and the SwiftSyntax visitor.
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
}
