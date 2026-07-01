# Modeling Assertions

Bumper Bowling does not overlap with SwiftLint.

SwiftLint owns Swift style: formatting, naming, whitespace, line length, sorted imports, brace placement, and local code smells.

Bumper Bowling owns architecture and modeling policy when that policy is visible to SwiftSyntax. It starts by declaring the architecture the repository wants, then derives violations from that contract.

## Example

This configuration says the domain layer owns its paths, avoids test frameworks, exposes explicit domain surfaces, uses typed identity, keeps state immutable, prefers a functional core, and models parser progress as an enum state machine.

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
        Layer(.core) {
            Owns("Sources/Core")
            Modules("Core")
            DoesNotUse("XCTest", "Testing", severity: .error)
            Requires(.explicitDomainSurfaces, .typedIdentity, .immutableState, .functionalCore, severity: .error)
            Requires(.enumStateMachine, severity: .error, in: "Sources/Core/**/*Parser.swift")
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

Layer usage and modeling assertions have a severity:

```swift
DoesNotUse("XCTest", "Testing", severity: .error)
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
Requires(.enumStateMachine, severity: .error, in: "Sources/Core/**/*Parser.swift")
```

That keeps strong modeling constraints intentional, local, and reviewable.

## What This Means

`Requires(.immutableState)` is not a formatting preference. It asserts that domain state should be immutable after construction.

`Requires(.functionalCore)` is not a formatting preference. It asserts that configured paths should not contain imperative constructs SwiftSyntax can observe, such as loops, assignments, mutable bindings, `inout` expressions, and `mutating` declarations.

`Requires(.typedIdentity)` is not a naming convention. It asserts that identity and validation should be modeled as types at the boundary instead of carried through the domain as raw strings.

`Requires(.explicitDomainSurfaces)` is not a local Swift preference. It asserts that domain surfaces should be explicit enough for architectural review.

`Requires(.enumStateMachine)` is not a parser style rule. It asserts that parser state should be modeled as enum cases carrying their data, so invalid parser states are harder to construct.

## Boundary

If the rule is about how code looks, use SwiftLint.

If the rule is about what architectural states are allowed to exist, and SwiftSyntax can observe enough source facts to check it deterministically, it belongs in Bumper Bowling.
