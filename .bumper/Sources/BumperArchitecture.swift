import BumperBowlingCore

extension ComponentShape {
    static let bumperEngine = ComponentShape {
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

    static let thinCommandAdapter = ComponentShape {
        MayDependOn(.core)
        DoesNotDependOn(.tests)
        MayUse(.foundation)
        Requires(.immutableStoredState, .typedIdentity, severity: .error)
    }

    static let testSupportBoundary = ComponentShape {
        MayDependOn(.core)
        DoesNotDependOn(.cli)
        MayUse(.foundation)
        Requires(.immutableStoredState, .typedIdentity, severity: .error)
    }
}

extension AssertionShape {
    static let bumperGlobal = AssertionShape {
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
