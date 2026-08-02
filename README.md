# Bumper Bowling

[![CI](https://github.com/RoyalPineapple/BumperBowling/actions/workflows/ci.yml/badge.svg)](https://github.com/RoyalPineapple/BumperBowling/actions/workflows/ci.yml)

Bumper Bowling makes Swift architecture executable.

Architecture is a contract for ownership, dependencies, and code shape. A
useful contract lives with the source, runs in CI, and explains each failure.
Bumper Bowling gives a Swift repository that contract.

You write policy in Swift. Bumper Bowling parses source with SwiftSyntax,
evaluates typed rules, and reports evidence for every failure.

| Tool | Protects |
| --- | --- |
| Swift compiler | Language, type, and concurrency correctness |
| [SwiftLint](https://github.com/realm/swiftlint) | Style and local source conventions |
| Runtime tests | Application behavior |
| Bumper Bowling | Repository-specific source architecture |

Use Bumper Bowling for rules such as these:

- Only named components can import a framework.
- Component dependencies must follow a declared graph.
- A source path has one component owner.
- A boundary owns an unsafe concurrency escape hatch.
- A stored callback declares its isolation.

Each repository owns its vocabulary and policy. Bumper Bowling supplies one
typed rule engine for the architecture that the repository chooses.

## The Idea

Bumper Bowling turns this declaration:

```text
Core owns these files.
CLI can depend on Core.
Core uses Foundation only.
```

into a repeatable source check. A failed check identifies the file, source
location, observed fact, and required architecture.

This makes architecture part of normal development. A developer can change a
rule, add a focused fixture, run the check, and review a clear result.

## Get Started

Add Bumper Bowling to a Swift package at a release tag:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/RoyalPineapple/BumperBowling.git", from: "0.6.0")
]
```

The package provides `BumperBowlingCore` for configuration and tests. It also
provides the `bumper` command-line tool.

Run these commands from the repository root:

```bash
swift run bumper init .
swift run bumper lint .
swift run bumper test .
```

`bumper init` writes `BumperBowling.swift`. `bumper lint` checks the
repository. `bumper test` runs repository-owned tests for custom rules.

For an advisory CI rollout, use JSON output and a baseline:

```bash
swift run bumper lint . --format json --fail-on none
swift run bumper baseline create . --output .bumper-baseline.json
swift run bumper lint . --baseline .bumper-baseline.json --fail-on error
```

## Declare The Architecture

`BumperBowling.swift` declares one `BumperProject` named `bumper`. A
project-owned `ComponentKey` enum makes component references compiler-checked.

```swift
import BumperBowlingCore

enum AppComponent: String, ComponentKey {
    case core
    case cli
}

let bumper = BumperProject {
    Included { "Sources" }

    Architecture(AppComponent.self) {
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

    Rules {
        DependencyBoundaries(.error)
        SingleOwner(.error)
        AcyclicDeclaredDependencies(.error)
    }
}
```

Each component declares three facts:

- `Owns` identifies the source paths that belong to the component.
- `Modules` identifies the imports that represent the component.
- `MayDependOn` identifies allowed component dependencies.

The engine checks each component against its declared ownership, dependencies,
imports, declarations, stored state, and selected syntax facts. A component
policy selects the facts that matter for that component.

## Compose Your Own Vocabulary

Composition is Bumper Bowling's main extension point. The engine provides
small typed pieces. A repository combines those pieces into names that fit its
codebase.

| Piece | Groups |
| --- | --- |
| `ComponentRequirement` | Source-fact requirements |
| `ComponentShape` | Component elements |
| `AssertionShape` | Repository-level rule configuration |

For example, a repository can define a reusable domain policy:

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

Apply that policy explicitly:

```swift
Component(.core) {
    Owns("Sources/Core")
    Applies(.domain)
}
```

`Applies(.domain)` adds the policy to the current component. The component's
owned paths provide the default scope for its requirements.

A shape can apply another shape. Use `RuleDefinition` and `RuleScope` for a
repository-specific check. Built-in and custom rules use the same parser, fact
cache, and report format.

The project applies each value explicitly. A local file or package provides
the Swift values that the project chooses to use.

Put repository-only vocabulary in `.bumper/Sources`. For vocabulary shared by
multiple repositories, use `.bumper/Package.swift` with a `BumperRules`
library product.

```text
.bumper/
  Package.swift
  Sources/BumperRules/Rules.swift
```

## Add A Custom Rule

Use a `RuleDefinition` when the standard architecture DSL cannot state the
policy. Add that rule to `Rules { ... }` with built-in rules.

```swift
import BumperBowlingCore

let projectRules = RuleSet {
    Rules.repository(
        "project.import_allow_list",
        severity: .error,
        summary: "The project imports only allowed modules."
    ) { context in
        let allowed = Set(["Foundation"])
        return try context.facts(BuiltInFacts.imports).occurrences
            .filter { !allowed.contains($0.module.rawValue) }
            .map { occurrence in
                RuleFailure(
                    path: occurrence.path,
                    message: "This import is not allowed.",
                    evidence: ViolationEvidence(
                        observed: occurrence.module.rawValue,
                        expectation: "an allowed import"
                    )
                )
            }
    }
}
```

```swift
Rules {
    DependencyBoundaries(.error)
    projectRules
}
```

Every rule can run in memory with `BumperBowlingTestSupport`. See
[rule authoring](docs/RULE_AUTHORING.md) for the authoring ladder, fixtures,
typed facts, queries, and raw `SyntaxVisitor` rules.

## Run In CI

This repository uses its own public API. CI runs package tests and:

```bash
swift run bumper lint .
```

You can run the same architecture check from a Swift test:

```swift
let report = try await BumperCommands.lint(
    root: projectRoot,
    configuration: bumper.architecture
)
```

Record error violations as test failures in the test framework that your
repository uses.

## Commands

```text
bumper init [root]             Write a starter configuration.
bumper lint [root]             Check the repository.
bumper test [root]             Run repository-owned rule tests.
bumper scan [root]             Show the observed architecture graph.
bumper baseline create [root]  Write a JSON baseline.
bumper snapshot [root]         Render the declared architecture.
bumper config [root]           Check configuration loading.
bumper explain <path>          Show facts for one file.
```

`lint` and `scan` accept `--format markdown|json`. `lint` accepts
`--fail-on`, `--baseline`, `--progress`, and `--timings`.

## Configuration Execution

`BumperBowling.swift` is a Swift program, like `Package.swift`. Bumper Bowling
compiles it into a cached runner and evaluates it in an isolated process.

The runner has two modes. `describe` reports the architecture configuration.
`evaluate` receives scanned source files, parses each file once, and reports
the rule result. The `bumper` process performs repository scanning. The runner
uses a restricted environment for configuration evaluation.

The runner builds once for an unchanged configuration. By default, it uses a
release build. Use `BUMPER_RUNNER_BUILD_CONFIGURATION=debug` on a smaller CI
host to reduce the initial build time.

Use `BUMPER_CACHE_DIR` to persist the runner cache in CI:

```bash
BUMPER_CACHE_DIR=.build/bumper-cache swift run bumper lint .
```

Evaluation has a 60-second default limit. Set
`BUMPER_EVALUATION_TIMEOUT_SECONDS` to a positive number of seconds for a
larger repository.

## Fact Surface

Bumper Bowling builds its evidence from SwiftSyntax-visible facts. These facts
include source ownership, imports, declarations, stored properties, and syntax
constructs.

Read [the SwiftSyntax surface](docs/SWIFTSYNTAX_SURFACE.md) for the exact fact
set. Read [the configuration specification](docs/DSL_SPEC.md) for all DSL
forms.

## Development

```bash
BUMPER_RUNNER_BUILD_CONFIGURATION=debug swift test
swift run bumper lint .
```

The test override avoids repeated optimized builds for fixture runners. The
repository also checks its own architecture.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Configuration language](docs/DSL_SPEC.md)
- [Rule authoring](docs/RULE_AUTHORING.md)
- [SwiftSyntax surface](docs/SWIFTSYNTAX_SURFACE.md)
- [Release checklist](docs/RELEASE_CHECKLIST.md)

## License

Apache License 2.0. See [LICENSE](LICENSE).
