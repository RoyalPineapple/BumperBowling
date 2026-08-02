# Bumper Bowling

[![CI](https://github.com/RoyalPineapple/BumperBowling/actions/workflows/ci.yml/badge.svg)](https://github.com/RoyalPineapple/BumperBowling/actions/workflows/ci.yml)

**Bumper Bowling keeps all players in the same lane.**

Bumper Bowling is a programmable architecture validator for Swift codebases.
It codifies and enforces the unwritten rules that developers, reviewers, CI,
and agents rely on.

Every codebase has rules for ownership, dependencies, and code shape. Teams
often learn these rules through review, incidents, and experience. Bumper
Bowling puts them in source control, validates them in CI, and explains each
failure with source evidence.

You write policy in Swift. Bumper Bowling parses source with SwiftSyntax,
evaluates typed rules, and reports evidence for every failure.

Use Bumper Bowling for rules such as these:

- Only named components can import a framework.
- Component dependencies must follow a declared graph.
- A source path has one component owner.
- A boundary owns an unsafe concurrency escape hatch.
- A stored callback declares its isolation.

Each repository owns its vocabulary and policy. Bumper Bowling supplies one
typed rule engine for the architecture that the repository chooses.

## From Rule To Evidence

Bumper Bowling turns this declaration:

```text
Core owns these files.
CLI can depend on Core.
Core uses Foundation only.
```

into repeatable source validation. A failure identifies the file, source
location, observed fact, and required architecture.

```text
Sources/CLI/Command.swift:14
CLI imports undeclared component Database (database)
```

Developers, reviewers, CI, and agents use the same contract. A team can change
a rule, add a focused fixture, run the validation, and review a clear result.

The name describes the job. A bowler chooses the throw. The bumpers keep the
ball in its lane. Bumper Bowling lets a team move quickly inside the boundaries
that it declares.

| Tool | Protects |
| --- | --- |
| Swift compiler | Language, type, and concurrency correctness |
| [SwiftLint](https://github.com/realm/swiftlint) | Style and local source conventions |
| Runtime tests | Application behavior |
| Bumper Bowling | Repository-specific source architecture |

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
```

`bumper init` writes `BumperBowling.swift`. `bumper lint` validates the
repository.

For an advisory CI rollout, use JSON output and a baseline:

```bash
swift run bumper lint . --format json --fail-on none
swift run bumper baseline create . --output .bumper-baseline.json
swift run bumper lint . --baseline .bumper-baseline.json --fail-on error
```

## Declare The Architecture

`BumperBowling.swift` declares one `BumperProject` named `bumper`. The compiler
validates component references through a project-owned `ComponentKey` enum.

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

This example declares five parts of the architecture:

- `Owns` identifies the source paths that belong to the component.
- `Modules` identifies the imports that represent the component.
- `MayDependOn` identifies allowed component dependencies.
- `MayUse` identifies allowed platform capabilities.
- `Requires` identifies required source facts.

The engine validates each component against its declared ownership, dependencies,
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
    static let foundationOnly = ComponentShape {
        MayUse(.foundation)
        DoesNotUse(.uiKit, .testing)
    }

    static let domain = ComponentShape {
        Applies(.foundationOnly)
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
repository-specific rule. Built-in and custom rules use the same parser, fact
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

Apply the same policy to each component that shares this architecture:

```swift
Component(.pricing) {
    Owns("Sources/Pricing")
    Applies(.domain)
}

Component(.catalog) {
    Owns("Sources/Catalog")
    Applies(.domain)
}
```

Small source-fact requirements become reusable vocabulary. That vocabulary
becomes component policy. The project then validates each component with the
same policy.

## Use The Right Level

Bumper Bowling gives each repository several levels of rule authoring:

| Need | Use |
| --- | --- |
| Component ownership and dependencies | Architecture DSL |
| Reusable source policy | `ComponentRequirement` and `ComponentShape` |
| Repository-wide policy | `AssertionShape` |
| Standard ownership and traversal rules | `Rules.*` shapers |
| Repository-specific fact rules | `RuleDefinition` |
| File-level syntax rules | `Rules.files` and `SyntaxQuery` |
| Direct syntax traversal | `SyntaxVisitor` |

These standard shapers validate ownership beyond imports:

```swift
Rules.singleDeclaration(
    "AppEnvironment",
    owner: "Sources/App"
)

Rules.constructionOwnership(
    "URLSession",
    allowed: .under("Sources/Networking")
)
```

Component requirements can validate code shape:

```swift
Component(.core) {
    Owns("Sources/Core")
    RequiresScoped(.enumStateMachine, "Sources/Core/Parser")
}
```

Use a `RuleDefinition` when the repository needs a new typed fact rule. Add
the rule to the same `Rules` block as the standard rules:

```swift
Rules {
    DependencyBoundaries(.error)
    projectRules
}
```

All levels use the same parser, fact cache, and report format. Every custom
rule can run in memory with `BumperBowlingTestSupport`:

```bash
swift run bumper test .
```

See [rule authoring](docs/RULE_AUTHORING.md) for fixtures, typed facts,
queries, and direct `SyntaxVisitor` rules.

## Run In CI

This repository uses its own public API. CI runs package tests and:

```bash
swift run bumper lint .
```

You can run the same architecture validation from a Swift test:

```swift
let report = try await BumperCommands.lint(
    root: projectRoot,
    configuration: bumper.architecture
)
```

Record error violations as test failures in the test framework that your
repository uses.

## Work With Agents

Bumper Bowling gives an agent the architectural context that code review often
supplies after a change. The agent reads the repository rules, makes a change,
runs Bumper Bowling, and repairs any violation.

The rules are ordinary Swift code. An agent can evolve them when the
architecture changes. The policy change, its fixtures, and the source change
then appear together in review.

The repository includes a Codex skill for this workflow:

```text
skills/compose-bumper-rules/
```

The skill guides an agent to reuse local vocabulary, choose the right rule
level, write focused fixtures, and validate the completed change.

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
repository also validates its own architecture.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Configuration language](docs/DSL_SPEC.md)
- [Rule authoring](docs/RULE_AUTHORING.md)
- [From SwiftSyntax to an architecture rule](docs/CANONICAL_TRAVERSAL.md)
- [SwiftSyntax surface](docs/SWIFTSYNTAX_SURFACE.md)
- [Release checklist](docs/RELEASE_CHECKLIST.md)

## License

Apache License 2.0. See [LICENSE](LICENSE).
