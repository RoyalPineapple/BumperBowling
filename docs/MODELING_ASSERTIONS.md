# Modeling Assertions

Bumper Bowling does not overlap with SwiftLint.

SwiftLint owns Swift style: formatting, naming, whitespace, line length, sorted imports, brace placement, and local code smells.

Bumper Bowling owns architecture and modeling policy when that policy is visible to SwiftSyntax. It starts by declaring the shape the repository wants, then derives violations from that contract.

## Example

This configuration says the domain component owns its paths, may use Foundation, exposes explicit domain surfaces, uses typed identity, keeps stored state immutable, disallows selected imperative constructs, and models parser progress as an enum state machine.

```swift
import BumperBowlingCore

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
            Owns("Sources/Core")
            Modules("Core")
            MayUse(.foundation)
            Requires(.explicitDomainSurfaces, .typedIdentity, .immutableStoredState, severity: .error)
            Disallows(.assignment, .loop, .mutableBinding, .inoutExpression, .mutatingDeclaration, severity: .error)
            RequiresScoped(.enumStateMachine, "Sources/Core/**/*Parser.swift", severity: .error)
        }
    }
}
```

## How The DSL Pushes Policy

The DSL makes architectural policy concrete before enforcement starts. The center is the architecture you want, not a pile of disconnected prohibitions.

Every assertion has a named scope:

```swift
Owns("Sources/Core")
```

That keeps a rule from becoming vague repo-wide pressure.

Component usage and modeling assertions have a severity:

```swift
MayUse(.foundation, severity: .error)
Requires(.typedIdentity, severity: .error)
```

That forces the team to decide whether a policy is advisory or lane-keeping.

Every assertion names an expected source fact:

```swift
Requires(.typedIdentity, severity: .error)
```

That keeps Bumper Bowling tied to observable SwiftSyntax facts instead of subjective review language.

Every opt-in assertion is explicit:

```swift
RequiresScoped(.enumStateMachine, "Sources/Core/**/*Parser.swift", severity: .error)
```

That keeps strong modeling constraints intentional, local, and reviewable.

## What This Means

`Requires(.immutableStoredState)` is not a formatting preference. It asserts that domain state should be immutable after construction.

`Disallows(.assignment, .loop, .mutableBinding)` is not a formatting preference. It asserts that configured paths should not contain those imperative constructs when SwiftSyntax observes them.

`Requires(.typedIdentity)` is not a naming convention. It asserts that identity and validation should be modeled as types at the boundary instead of carried through the domain as raw strings.

`Requires(.explicitDomainSurfaces)` is not a local Swift preference. It asserts that domain surfaces should be explicit enough for architectural review.

`Requires(.enumStateMachine)` is not a parser style rule. It asserts that parser state should be modeled as enum cases carrying their data, so invalid parser states are harder to construct.

## Boundary

If the rule is about how code looks, use SwiftLint.

If the rule is about what architectural states are allowed to exist, and SwiftSyntax can observe enough source facts to check it deterministically, it belongs in Bumper Bowling.
