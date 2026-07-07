# Bumper Vocabulary

## Terms

- `ComponentRequirement`: a reusable set of source-fact rules.
- `ComponentShape`: a reusable bundle of component DSL elements.
- `AssertionShape`: a reusable bundle of repo-level rule configuration.
- `RuleConfiguration`: the evaluated/scoped policy Bumper Bowling runs.
- `Scope`: paths, components, or exclusions where a rule applies.

## Core Pattern

```swift
import BumperBowlingCore

extension ComponentRequirement {
    static let domainCore = ComponentRequirement(
        .explicitDomainSurfaces,
        .typedIdentity,
        .immutableStoredState
    )
}

extension ComponentShape {
    static let domain = ComponentShape {
        MayUse(.foundation)
        DoesNotUse(.uiKit, .swiftUI)
        Requires(.domainCore, severity: .error)
    }
}

extension AssertionShape {
    static let global = AssertionShape {
        DependencyBoundaries(.error)
        SingleOwner(.error)
        AcyclicDeclaredDependencies(.error)
    }
}
```

Then apply it:

```swift
let configuration = BumperConfiguration {
    Architecture {
        Component(.core) {
            Owns("Sources/Core")
            Applies(.domain)
        }
    }

    Assertions {
        ApplyAssertions(.global)
    }
}
```

## Guardrails

- Do not promise facts SwiftSyntax cannot observe.
- Do not auto-apply rules from a package. Importing only makes values available.
- Do not make consumer vocabulary sound canonical for every repo.
- Prefer one clear shape over many tiny speculative shapes.
