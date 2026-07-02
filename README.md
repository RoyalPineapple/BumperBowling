# Bumper Bowling

[![CI](https://github.com/RoyalPineapple/BumperBowling/actions/workflows/ci.yml/badge.svg)](https://github.com/RoyalPineapple/BumperBowling/actions/workflows/ci.yml)

Bumper Bowling keeps agents in their lane: declare the shape your Swift codebase should have, then validate every change against that shape.

It is meant to run beside SwiftLint. SwiftLint owns local Swift style and code smells; Bumper Bowling owns the formal codebase shape: what each component owns, may depend on, may use, and must prove from SwiftSyntax facts.

## Status

Bumper Bowling is 0.0 shaping work.

The current CLI is useful for proving the core model on this repository. The Swift DSL is available as the typed assertion API and sample authoring shape, but `bumper lint` still uses the built-in repository configuration. Loading `BumperBowling.swift` from disk is intentionally post-MVP.

## Model

```text
SwiftSyntax reads the code
Bumper records raw source facts
Those facts form an ArchitectureGraph
The Swift DSL encodes typed assertions
Lint runs math over the graph
```

Bumper Bowling only asserts architecture visible to SwiftSyntax plus configured repo shape. It does not resolve symbols, infer types, expand macros semantically, or prove compiler-level dependencies. See [docs/SWIFTSYNTAX_SURFACE.md](docs/SWIFTSYNTAX_SURFACE.md) for the current fact surface.

The core is intentionally lean: parse raw SwiftSyntax facts, normalize them into a graph, then run deterministic operations over that graph: set membership, path scope, edge checks, and cycle detection.

Bumper keeps receipts. Every finding should trace back to an observed graph fact, and `scan`, `explain`, and `snapshot` expose the evidence Bumper used.

Facts become rules when they are scoped by the DSL. You can use Bumper's semantic shorthand or compose your own:

```swift
extension ComponentRequirement {
    static let valueCore = ComponentRequirement(
        .explicitDomainSurfaces,
        .typedIdentity,
        .computedState,
        .immutableStoredState,
        .functionalCore
    )
}
```

That shorthand still lowers into raw fact assertions over stored properties, syntax constructs, and enum declarations.

The DSL starts from the shape you want:

```swift
Component(.core) {
    Owns("Sources/BumperBowlingCore")
    Modules("BumperBowlingCore")
    MayUse(.foundation)
    Requires(.valueCore, severity: .warning)
}
```

The rule engine derives violations from that contract. Bumper Bowling should not be a pile of disconnected "do not" rules.

`bumper scan` and `bumper snapshot` expose the architecture the code currently expresses: owned files, imports, declarations, properties, selected imperative constructs, subsystem edges, and enabled assertions. They are receipts for the declared shape.

The graph is a normalized projection of SwiftSyntax facts, not a copy of the full SwiftSyntax tree. Bumper Bowling should add graph facts only when a rule can use them.

## Agent Workflow

Bumper Bowling is designed for agentic coding loops:

1.  Declare the lanes in the DSL.
2.  Let an agent make a change.
3.  Run `bumper lint`.
4.  Use the receipt to see the observed graph fact, the declared lane, and the mismatch.
5.  Repair the smallest thing: move the code, change the dependency, or intentionally update the lane.

The goal is not to make agents timid. The goal is to give them fast, formal feedback when they cross an architectural boundary.

## What It Checks

MVP rules:

- `forbidden_import`: disallow configured imports in linted source files.
- `subsystem_boundary`: require subsystem imports to match declared dependencies.
- `duplicate_ownership`: detect overlapping subsystem path ownership.
- `declared_dependency_cycle`: reject cycles in declared subsystem dependencies.
- `stored_properties`: enforce typed assertions over SwiftSyntax stored property facts.
- `syntax_constructs`: enforce typed assertions over SwiftSyntax construct facts.
- `enum_state_machine`: require parser files to declare an enum state machine.

The `stored_properties` rule is deliberately syntax-first in 0.0. It checks explicit stored-property type annotations for mutable stored properties, `Any`, `any ...`, and raw `String` in configured paths. It does not perform compiler-level type inference or full public API analysis. See [docs/MODELING_ASSERTIONS.md](docs/MODELING_ASSERTIONS.md) for an example of using these assertions without overlapping SwiftLint.

## Quick Start

```bash
swift test
swift run bumper lint .
swift run bumper scan .
swift run bumper snapshot .
swift run bumper explain Sources/BumperBowlingCore/ArchitectureLinter.swift
```

`lint` exits nonzero only for `error` findings. `note` and `warning` findings are reported but do not fail the run.

## Commands

```bash
bumper init [root]
bumper lint [root]
bumper scan [root]
bumper snapshot [root]
bumper explain <path>
```

`bumper init` writes a sample `BumperBowling.swift` file. In 0.0 that file is documentation and typed API shape, not a config file the CLI executes.

## Configuration Shape

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
            Owns("Sources/BumperBowlingCore")
            Modules("BumperBowlingCore")
            MayUse(.foundation)
            Requires(
                .explicitDomainSurfaces,
                .typedIdentity,
                .immutableStoredState,
                severity: .warning
            )
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
        AcyclicDeclaredDependencies(.error)
    }
}
```

DSL constructors parse strings into typed values at the boundary. `Owns`, `MayDependOn`, `DoesNotDependOn`, `MayUse`, `DoesNotUse`, `Requires`, and `Disallows` compile down to typed graph assertions over parsed SwiftSyntax facts, not loose strings.

## Architecture

Bumper Bowling is SwiftSyntax-driven. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the system shape, [docs/SWIFTSYNTAX_SURFACE.md](docs/SWIFTSYNTAX_SURFACE.md) for the observable fact surface, and [docs/ARCHITECTURE_SNAPSHOT.md](docs/ARCHITECTURE_SNAPSHOT.md) for the generated commands, pipeline, and rule snapshots.

Swift is the only language surface in 0.0. SwiftSyntax and SwiftParser stay inside `SwiftFileParser`; Bumper Bowling wraps those facts with DSL assertions.

## Development

This package uses Swift 6 strict concurrency settings.

```bash
swift test
swift run bumper lint .
```

CI runs both commands on macOS.

SwiftLint is intentionally adjacent. The repo includes `.swiftlint.yml`, but Bumper Bowling does not shell out to SwiftLint and is not a replacement for it.

Regenerate the checked-in architecture snapshot with:

```bash
swift run -q bumper snapshot . > docs/ARCHITECTURE_SNAPSHOT.md
```

## Non-Goals For 0.0

- No JSON config.
- No plugin system.
- No generated accessors.
- No dynamic member lookup config trick.
- No autocorrect.
- No diff mode or baselines.
- No semantic analyzer.
- No execution of arbitrary `BumperBowling.swift` files by the CLI.

## License

Apache License 2.0. See [LICENSE](LICENSE).
