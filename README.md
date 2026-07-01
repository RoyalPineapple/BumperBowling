# Bumper Bowling

[![CI](https://github.com/RoyalPineapple/BumperBowling/actions/workflows/ci.yml/badge.svg)](https://github.com/RoyalPineapple/BumperBowling/actions/workflows/ci.yml)

Bumper Bowling is a tiny Swift 6 architectural linter for Swift repositories.

It is meant to run beside SwiftLint. SwiftLint owns local Swift style and code smells; Bumper Bowling owns architectural boundaries, dependency direction, and repo-specific taste.

## Status

Bumper Bowling is 0.0 shaping work.

The current CLI is useful for proving the core model on this repository. The Swift DSL is available as the typed configuration API and sample authoring shape, but `bumper lint` still uses the built-in repository configuration. Loading `BumperBowling.swift` from disk is intentionally post-MVP.

## What It Checks

MVP rules:

- `forbidden_import`: disallow configured imports in linted source files.
- `subsystem_boundary`: require subsystem imports to match declared dependencies.
- `duplicate_ownership`: detect overlapping subsystem path ownership.
- `dependency_cycle`: reject cycles in configured subsystem dependencies.
- `domain_models`: enforce syntax-first domain model taste rules.
- `enum_state_machine`: require parser files to declare an enum state machine.

The `domain_models` rule is deliberately syntax-first in 0.0. It checks explicit stored-property type annotations for mutable stored properties, `Any`, `any ...`, and raw `String` in configured paths. It does not perform compiler-level type inference or full public API analysis.

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
```

DSL constructors parse strings into typed values at the boundary. The rule engine works with types like `SubsystemID`, `ModuleName`, and `RelativeFilePath`, not loose strings.

## Architecture

Bumper Bowling is adapter-driven. See [ARCHITECTURE_SNAPSHOT.md](ARCHITECTURE_SNAPSHOT.md) for the generated command flow, conceptual layers, rule snapshots, and 0.0 boundaries.

Swift is the only language adapter in 0.0. SwiftSyntax and SwiftParser stay inside `SwiftLanguageAdapter`; the adapter boundary exists so parsing stays isolated from the rule engine.

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
swift run -q bumper snapshot . > ARCHITECTURE_SNAPSHOT.md
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
