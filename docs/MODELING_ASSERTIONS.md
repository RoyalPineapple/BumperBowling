# Modeling Assertions

Bumper Bowling does not overlap with SwiftLint.

SwiftLint owns Swift style: formatting, naming, whitespace, line length, sorted imports, brace placement, and local code smells.

Bumper Bowling owns architecture and modeling policy when that policy is visible to SwiftSyntax. It starts with raw parsed facts, projects them into a graph, then applies typed Swift assertions as lean graph operations.

## Example

This configuration says the core component owns its paths, may use Foundation, disallows selected stored-property facts, disallows selected syntax constructs, and models parser progress as an enum state machine.

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
            Requires(
                .noAnyStoredProperties,
                .noBroadExistentialStoredProperties,
                .noRawStringStoredProperties,
                .immutableStoredState,
                severity: .error
            )
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

Component usage and fact assertions have a severity:

```swift
MayUse(.foundation, severity: .error)
Requires(.noRawStringStoredProperties, severity: .error)
```

That forces the team to decide whether a policy is advisory or lane-keeping.

Every assertion names an expected source fact:

```swift
Requires(.noRawStringStoredProperties, severity: .error)
```

That keeps Bumper Bowling tied to observable SwiftSyntax facts instead of subjective review language.

Every opt-in assertion is explicit:

```swift
RequiresScoped(.enumStateMachine, "Sources/Core/**/*Parser.swift", severity: .error)
```

That keeps strong modeling constraints intentional, local, and reviewable.

## What This Means

`Requires(.immutableStoredState)` is not a formatting preference. It asserts that SwiftSyntax should not observe mutable stored properties in the configured scope.

`Disallows(.assignment, .loop, .mutableBinding)` is not a formatting preference. It asserts that configured paths should not contain those syntax constructs when SwiftSyntax observes them.

`Requires(.noRawStringStoredProperties)` is not a naming convention. It asserts that SwiftSyntax should not observe stored properties explicitly typed as `String` in the configured scope.

`Requires(.noAnyStoredProperties)` and `Requires(.noBroadExistentialStoredProperties)` are not local Swift preferences. They assert that SwiftSyntax should not observe stored properties explicitly typed as `Any` or `any ...` in the configured scope.

`Requires(.enumStateMachine)` is not a parser style rule. It asserts that parser state should be modeled as enum cases carrying their data, so invalid parser states are harder to construct.

## Boundary

If the rule is about how code looks, use SwiftLint.

If the rule is about what architectural states are allowed to exist, and SwiftSyntax can observe enough source facts to check it deterministically, it belongs in Bumper Bowling.
