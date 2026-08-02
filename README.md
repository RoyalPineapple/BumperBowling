# Bumper Bowling

[![CI](https://github.com/RoyalPineapple/BumperBowling/actions/workflows/ci.yml/badge.svg)](https://github.com/RoyalPineapple/BumperBowling/actions/workflows/ci.yml)

**Turn your Swift repository's unwritten rules into rules everyone can run.**

Every mature codebase relies on truths that live outside its type system.
Senior developers carry them through review. New contributors learn them after
mistakes. Agents infer them from scattered examples.

Bumper Bowling gives those truths names, scopes, tests, and source evidence.
Developers, reviewers, CI, and agents all use the same architecture policy.

A repository can require facts such as these:

- Every `Identifiable.id` uses a typed value instead of a raw string.
- Every parser file declares an enum state machine.
- Canonical values have one declaration and approved construction owners.
- Recursive traversal stays with the subsystem that owns the hierarchy.
- Stored callbacks declare the repository's required isolation.
- Every feature file contains exactly one reducer.

Write the policy in Swift. Start with reusable requirements and standard
rules. Compose them into names from your codebase. Drop down to typed facts,
SwiftSyntax queries, or a raw visitor when the rule needs more.

Bumper Bowling provides one path from source to evidence:

```text
SwiftSyntax -> typed observations -> scopes -> rules -> source evidence
```

**Bumper Bowling makes SwiftSyntax practical for enforcing the truths that
define your codebase.**

The name describes the workflow. Your team declares the lanes. A developer or
agent takes the shot. CI catches a wild change before it merges and bumps it
back toward the lane with exact source evidence.

## Turn One Idea Into One Rule

Suppose one subsystem owns recursive traversal of a tree:

```swift
Rules {
    Rules.canonicalTraversal(
        root: "Tree",
        structuralCase: "branch",
        owners: .under("Sources/TreeTraversal")
    )
}
```

Bumper Bowling combines function declarations, parameter types, case patterns,
and recursive call groups. It then reports a traversal outside the owner:

```text
Sources/Features/Search/Search.swift:3
search recursively traverses Tree.branch outside its owners.
```

`Tree`, `branch`, and `Sources/TreeTraversal` belong to the repository. Bumper
Bowling supplies the SwiftSyntax composition, rule engine, and report.

Read [Build An Architecture Rule From The Ground Up](docs/RULE_FROM_THE_GROUND_UP.md)
to follow every step behind this convenience.

## Make Architecture A Swift Vocabulary

Small source facts become names that fit the codebase:

```swift
extension ComponentRequirement {
    static let valueModel = ComponentRequirement(
        .explicitDomainSurfaces,
        .typedIdentity,
        .immutableStoredState
    )
}

extension ComponentShape {
    static let domain = ComponentShape {
        MayUse(.foundation)
        Requires(.valueModel)
    }
}
```

Apply that vocabulary wherever the architecture requires it:

```swift
Component(.catalog) {
    Owns("Sources/Catalog")
    Applies(.domain)
}

Component(.pricing) {
    Owns("Sources/Pricing")
    Applies(.domain)
}
```

The repository defines what `valueModel` and `domain` mean. Bumper Bowling
validates every applied component with the same composed policy.

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

## Keep The Vocabulary With The Code

Architecture vocabulary is ordinary Swift. Keep repository-specific values in
`.bumper/Sources` beside the project configuration:

```text
.bumper/
  Sources/
    ArchitectureVocabulary.swift
    ProjectRules.swift
BumperBowling.swift
```

`BumperBowling.swift` chooses every applied value explicitly. Importing a file
only makes its Swift values available.

Share vocabulary across repositories through a local Swift package with a
`BumperRules` library product:

```text
.bumper/
  Package.swift
  Sources/BumperRules/Rules.swift
```

The policy remains reviewable Swift code. A change to the architecture, its
rules, its fixtures, and the affected source can travel together.

## Start High And Drop Down When Needed

Bumper Bowling exposes every level of its validation path:

| Need | Use |
| --- | --- |
| Component ownership and dependencies | Architecture DSL |
| Reusable source policy | `ComponentRequirement` and `ComponentShape` |
| Repository-wide policy | `AssertionShape` |
| Common ownership, construction, and traversal rules | `Rules.*` shapers |
| Repository-wide source analysis | `BuiltInFacts` and `Rules.repository` |
| Typed syntax matches and cardinality | `SyntaxQuery`, `Rules.assert`, and `Rules.forbid` |
| Per-file source policy | `Rules.files` |
| Direct SwiftSyntax traversal | `Rules.visitor` and `SyntaxVisitor` |

Use a short standard rule when it fits:

```swift
Rules.canonicalConstruction(
    "AppEnvironment",
    owners: .under("Sources/App/Bootstrap")
)
```

Compose a typed syntax rule when the repository has its own concept:

```swift
Rules.assert(
    functions().named("reduce"),
    cardinality: .exactly(1),
    id: "feature.one_reducer",
    summary: "Each feature file declares one reducer.",
    scope: .under("Sources/Features")
)
```

Extend a typed query or fact provider when the rule needs a new observation.
Use a raw `SyntaxVisitor` for a source walk that needs full SwiftSyntax access.

Every level uses the same parser, fact cache, rule protocol, and report. Add
built-in and repository-defined rules to the same block:

```swift
Rules {
    DependencyBoundaries(.error)
    projectRules
}
```

Test repository rules with focused source fixtures:

```bash
swift run bumper test .
```

See the [built-in catalog](docs/built-ins/README.md) for every included piece.
See [rule authoring](docs/RULE_AUTHORING.md) for custom facts, queries, visitors,
and fixtures.

## Run In CI

CI is where the bumpers protect the lane. Each proposed change takes a shot at
the codebase. A rule violation stops the wild shot before merge and points it
back toward the declared architecture.

Run the same validation locally and in CI:

```bash
swift run bumper lint .
```

This repository validates itself with its own public API. A Swift test can run
the same architecture policy:

```swift
let report = try await BumperCommands.lint(
    root: projectRoot,
    configuration: bumper.architecture
)
```

Record error violations as failures in the repository's test framework.

## Work With Agents

Bumper Bowling gives an agent the architectural context that code review often
supplies after a change. The agent reads the lanes before editing, makes the
change, and validates the result. Source evidence points an invalid change
back toward the architecture.

The rules are ordinary Swift code. An agent can update them as the architecture
evolves. The policy, its fixtures, and the source change then appear together
in review. Human and automated contributors work from the same contract.

The repository includes a Codex skill for this workflow:

```text
skills/compose-bumper-rules/
```

The skill guides an agent to reuse local vocabulary, choose the right rule
level, write focused fixtures, and validate the completed change.

Install the skill from the Bumper Bowling repository root:

```bash
mkdir -p "${CODEX_HOME:-$HOME/.codex}/skills"
ln -s "$PWD/skills/compose-bumper-rules" \
  "${CODEX_HOME:-$HOME/.codex}/skills/compose-bumper-rules"
```

Start a new Codex session, then invoke `$compose-bumper-rules` explicitly or
ask Codex to create, review, or refactor Bumper Bowling policy.

The skill follows the standard Codex skill layout. Its `agents/openai.yaml`
file supplies skill-list metadata and a default prompt.

## Commands

```text
bumper init [root]             Write a starter configuration.
bumper lint [root]             Validate the repository.
bumper test [root]             Run repository-owned rule tests.
bumper scan [root]             Show the observed architecture graph.
bumper baseline create [root]  Write a JSON baseline.
bumper snapshot [root]         Render the declared architecture.
bumper config [root]           Validate configuration loading.
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

Bumper Bowling turns SwiftSyntax into reusable observations. Built-in facts
cover files, imports, declarations, stored properties, calls, access,
containment, component edges, and recursive call groups.

Typed queries retain their concrete SwiftSyntax node type through composition.
Custom fact providers derive repository-wide observations once per run. A raw
visitor keeps the complete SwiftSyntax tree available for specialized rules.

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
- [Built-in rule authoring catalog](docs/built-ins/README.md)
- [Rule authoring](docs/RULE_AUTHORING.md)
- [Build a rule from the ground up](docs/RULE_FROM_THE_GROUND_UP.md)
- [SwiftSyntax surface](docs/SWIFTSYNTAX_SURFACE.md)
- [Release checklist](docs/RELEASE_CHECKLIST.md)

## License

Apache License 2.0. See [LICENSE](LICENSE).
