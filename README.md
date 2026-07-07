# Bumper Bowling

[![CI](https://github.com/RoyalPineapple/BumperBowling/actions/workflows/ci.yml/badge.svg)](https://github.com/RoyalPineapple/BumperBowling/actions/workflows/ci.yml)

Bumper Bowling is a Swift architecture linter.

[SwiftLint](https://github.com/realm/swiftlint) owns local style; Bumper
Bowling owns repo shape: which components exist, what paths they own, who may
depend on whom, and what each component must prove.

Declare your intended structure in familiar Swift. Bumper Bowling parses your
source with SwiftSyntax, turns what it sees into a graph of facts, and checks
that graph against your intent.

## Quick Start

```bash
swift run bumper init .
swift run bumper lint .
```

`bumper init` writes a starter `BumperBowling.swift`. `bumper lint` loads it,
scans the repo, and exits nonzero for `error` findings.

## Configuration

```swift
import BumperBowlingCore

let configuration = BumperConfiguration {
    Included {
        "Sources"
    }

    Architecture {
        Component(.core) {
            Owns("Sources/Core")
            Modules("Core")
            MayUse(.foundation)
            Requires(.explicitDomainSurfaces, .typedIdentity, severity: .warning)
        }

        Component(.cli) {
            Owns("Sources/CLI")
            Modules("CLI")
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

The same value works in your test suite, so architecture failures are just
test failures:

```swift
import BumperBowlingTesting
import Testing

@Test
func architectureStaysInLane() async throws {
    let bumperTest = BumperTest(configuration: configuration.architectureConfiguration)

    for message in try await bumperTest.errorMessages(root: projectRoot) {
        Issue.record(Comment(rawValue: message))
    }
}
```

The full vocabulary and every shipped rule live in the
[configuration language spec](docs/DSL_SPEC.md) and
[default rule sets](docs/DEFAULT_RULE_SETS.md).

## Consumer-Owned Shapes

Repositories can keep their own architecture vocabulary in `.bumper/Sources`.
Those Swift files compile beside `BumperBowling.swift`, so a project can define
its own `ComponentRequirement`, `ComponentShape`, and `AssertionShape` values
without waiting for Bumper Bowling to ship a named preset:

Bumper Bowling uses this pattern for itself in
`.bumper/Sources/BumperArchitecture.swift`.

```swift
// .bumper/Sources/HouseStyle.swift
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
        DoesNotUse(.uiKit, .testing)
        Requires(.domainCore, severity: .error)
    }
}
```

```swift
// BumperBowling.swift
Component(.core) {
    Owns("Sources/Core")
    Applies(.domain)
}
```

Shared local rule packages can use SwiftPM directly. If `.bumper/Package.swift`
exists, Bumper Bowling adds it to the generated runner and expects it to export
a `BumperRules` library product:

```text
.bumper/
  Package.swift
  Sources/BumperRules/Rules.swift
```

## Agent Skill

Bumper Bowling ships a Codex skill for agents composing repo-owned architecture
vocabulary:

```text
skills/compose-bumper-rules/
```

To install it locally:

```bash
mkdir -p ~/.codex/skills
cp -R skills/compose-bumper-rules ~/.codex/skills/
```

## Commands

```bash
bumper init [root]      # write a starter configuration
bumper lint [root]      # check the repo against it
bumper scan [root]      # show the architecture graph the code expresses
bumper snapshot [root]  # render the configured architecture
bumper config [root]    # how your configuration loads, and whether it is valid
bumper explain <path>   # what bumper sees in one file
```

## How The Configuration Loads

`BumperBowling.swift` is a program, not a data file — the same as
`Package.swift`. So Bumper Bowling loads it the way SwiftPM loads a manifest:
it compiles the file, runs it in a sealed-off process, and reads back the
configuration value the run produced.

The sealed-off process has no network, nowhere to write, and an empty
environment. It emits one thing — the configuration, as JSON — and nothing
else crosses back. Scanning and linting run in the `bumper` process itself,
never in configuration code.

The compile is cached against the file's contents, so it happens once per
change to `BumperBowling.swift`, not once per lint. An unchanged
configuration loads from cache with no build at all.

`bumper config` loads your configuration and tells you whether it is valid.

One honest caveat: compiling a configuration runs its build. Lint
repositories you trust.

## What It Can And Cannot See

Bumper Bowling sees what SwiftSyntax sees: files and ownership, imports,
public declarations, stored properties with explicit types, enum names, and
selected imperative constructs. It does no type inference and no symbol
resolution. Rules that need the compiler belong in a compiler-backed
analyzer, not this pass; the exact fact surface is in
[SWIFTSYNTAX_SURFACE.md](docs/SWIFTSYNTAX_SURFACE.md).

## Development

```bash
swift test
swift run bumper lint .
```

The repo lints itself; that is the main product test. The checked-in
architecture snapshot is generated by `bumper snapshot`.

## Docs

- [Architecture](docs/ARCHITECTURE.md)
- [Configuration language](docs/DSL_SPEC.md)
- [Default rule sets](docs/DEFAULT_RULE_SETS.md)
- [SwiftSyntax surface](docs/SWIFTSYNTAX_SURFACE.md)
- [Release checklist](docs/RELEASE_CHECKLIST.md)

## License

Apache License 2.0. See [LICENSE](LICENSE).
