# Bumper Bowling

[![CI](https://github.com/RoyalPineapple/BumperBowling/actions/workflows/ci.yml/badge.svg)](https://github.com/RoyalPineapple/BumperBowling/actions/workflows/ci.yml)

Bumper Bowling is a tiny Swift DSL for asserting architecture over SwiftSyntax-observed source facts.

It is meant to run beside SwiftLint. SwiftLint owns local Swift style and code smells; Bumper Bowling owns the positive architecture contract: what each layer owns, depends on, may depend on, does not use, and requires from its models.

## Status

Bumper Bowling is 0.0 shaping work.

The current CLI is useful for proving the core model on this repository. The Swift DSL is available as the typed assertion API and sample authoring shape, but `bumper lint` still uses the built-in repository configuration. Loading `BumperBowling.swift` from disk is intentionally post-MVP.

## Model

```text
SwiftSyntax observes source syntax
Bumper DSL declares architectural expectations
Bumper builds deterministic facts
Bumper normalizes facts into an ArchitectureGraph
Rules assert over the graph
```

Bumper Bowling only asserts architecture visible to SwiftSyntax plus configured repo shape. It does not resolve symbols, infer types, expand macros semantically, or prove compiler-level dependencies.

The DSL starts from the architecture you want:

```swift
Layer(.core) {
    Owns("Sources/BumperBowlingCore")
    Modules("BumperBowlingCore")
    DoesNotUse("XCTest", "Testing", severity: .error)
    Requires(.explicitDomainSurfaces, .typedIdentity, .immutableState, severity: .warning)
}
```

The rule engine derives violations from that contract. Bumper Bowling should not be a pile of disconnected "do not" rules.

`bumper scan` and `bumper snapshot` expose the architecture the code currently expresses: owned files, imports, declarations, properties, selected imperative constructs, subsystem edges, and enabled assertions. The scan is discovery; the DSL is the contract you choose to enforce.

The graph is a normalized projection of SwiftSyntax facts, not a copy of the full SwiftSyntax tree. Bumper Bowling should add graph facts only when a rule can use them.

That gives Bumper Bowling a useful loop: inspect the current graph, surface candidate assertions the code appears to follow, and let humans promote the meaningful ones into `BumperBowling.swift`.

## What It Checks

MVP rules:

- `forbidden_import`: disallow configured imports in linted source files.
- `subsystem_boundary`: require subsystem imports to match declared dependencies.
- `duplicate_ownership`: detect overlapping subsystem path ownership.
- `dependency_cycle`: reject cycles in configured subsystem dependencies.
- `domain_models`: enforce syntax-first domain modeling rules, including optional functional-core constraints.
- `enum_state_machine`: require parser files to declare an enum state machine.

The `domain_models` rule is deliberately syntax-first in 0.0. It checks explicit stored-property type annotations for mutable stored properties, `Any`, `any ...`, and raw `String` in configured paths. It does not perform compiler-level type inference or full public API analysis. See [docs/MODELING_ASSERTIONS.md](docs/MODELING_ASSERTIONS.md) for an example of using these assertions without overlapping SwiftLint.

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
```

DSL constructors parse strings into typed values at the boundary. `Owns`, `DependsOn`, `MayDependOn`, `DoesNotUse`, and `Requires` compile down to typed rules over `SubsystemID`, `ModuleName`, and `RelativeFilePath`, not loose strings.

## Architecture

Bumper Bowling is SwiftSyntax-driven. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the system shape and [docs/ARCHITECTURE_SNAPSHOT.md](docs/ARCHITECTURE_SNAPSHOT.md) for the generated commands, pipeline, and rule snapshots.

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
