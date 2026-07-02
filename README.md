# Bumper Bowling

[![CI](https://github.com/RoyalPineapple/BumperBowling/actions/workflows/ci.yml/badge.svg)](https://github.com/RoyalPineapple/BumperBowling/actions/workflows/ci.yml)

Bumper Bowling is a Swift architectural linter. Declare the lanes your code should stay in, add bumpers with the Swift DSL, and fail changes that violate the project's architectural rules.

It parses the repo into SwiftSyntax-backed facts and reports what it found. Each run is a frame with a scorecard: what Bumper Bowling observed, which rule failed, and which lane was involved.

It is meant to run beside SwiftLint. SwiftLint owns local Swift style and code smells; Bumper Bowling owns the formal codebase shape: what each component owns, may depend on, may use, and must prove from SwiftSyntax facts.

What makes Bumper Bowling interesting is the combination:

- A native Swift DSL for declaring architecture as typed values.
- A graph of observed source facts, not an ad hoc text scan.
- Deterministic assertions over that graph: ownership, dependencies, declarations, syntax facts, and modeling guarantees.
- Scorecards for humans and agents: `scan`, `explain`, `snapshot`, and test failures all point back to the facts Bumper Bowling observed.
- Two boring interfaces over one engine: a CLI for hooks/CI and a test harness for Swift Testing/XCTest.

## Vocabulary

Bumper Bowling uses the metaphor in the docs, but the API keeps the domain terms.

- **Lane**: a declared architectural boundary. In API terms, a lane is usually a `Component` with owned paths, module aliases, allowed dependencies, and allowed capabilities. A rule can also define a narrower lane with an explicit path scope.
- **Bumper**: a scoped architecture assertion.
- **House rules**: the repo's selected configuration and custom rule sets.
- **League rules**: rule sets Bumper Bowling ships. They are the same underlying type as house rules and can be used, combined, or modified.
- **Frame**: one lint, scan, snapshot, or test run.
- **Scorecard**: a report with observed facts and findings.

In API terms: lanes are components/scopes, bumpers are scoped rule sets or assertions, and scorecards are reports. The code should stay boring and obvious.

## Status

Bumper Bowling is 0.1 shaping work.

Bumper Bowling ships one engine and two dumb interfaces:

- `BumperBowlingCore`: parses SwiftSyntax facts, builds the graph, and evaluates rules.
- `bumper`: a CLI interface for shell workflows, commit hooks, and CI jobs. It loads `BumperBowling.swift`.
- `BumperBowlingTesting`: a test-suite interface for Swift Testing or XCTest. It accepts the same typed configuration value directly.

Both interfaces have configuration parity. The CLI uses a native Swift config file; tests use native Swift values.

## Model

```text
SwiftSyntax reads the code
Bumper Bowling records raw source facts
Those facts form an ArchitectureGraph
The Swift DSL encodes typed assertions
Lint runs math over the graph
```

Bumper Bowling only asserts architecture visible to SwiftSyntax plus configured repo shape. It does not resolve symbols, infer types, expand macros semantically, or prove compiler-level dependencies. See [docs/SWIFTSYNTAX_SURFACE.md](docs/SWIFTSYNTAX_SURFACE.md) for the current fact surface and [docs/COMPILER_REQUESTS.md](docs/COMPILER_REQUESTS.md) for checks that need compiler help.

The core is intentionally lean: parse raw SwiftSyntax facts, normalize them into a graph, then run deterministic operations over that graph: set membership, path scope, edge checks, and cycle detection.

Bumper Bowling keeps scorecards. Every finding should trace back to an observed graph fact, and `scan`, `explain`, and `snapshot` expose the evidence Bumper Bowling used.

Bumper Bowling does not duplicate SwiftSyntax's type universe. Raw syntax assertions use SwiftSyntax's own `SyntaxKind` values:

```swift
RequireSyntax(.enumDecl)
DisallowSyntax(.forceUnwrapExpr)
```

Richer local facts are computed as extensions on real SwiftSyntax nodes:

```swift
node.bumper.kind
variableDecl.bumper.isMutableBinding
variableDecl.bumper.storedProperties
```

That keeps SwiftSyntax as the source of truth while Bumper Bowling owns the assertion algebra.

Facts become rules when they are scoped by the DSL. You can use Bumper Bowling's semantic shorthand or compose your own:

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

`scan` and `snapshot` expose the architecture the code currently expresses: owned files, imports, declarations, properties, selected imperative constructs, subsystem edges, and enabled assertions. They are scorecards for the declared architecture.

The graph is a normalized projection of SwiftSyntax facts, not a copy of the full SwiftSyntax tree. Bumper Bowling should add graph facts only when a rule can use them.

## Lane

Bumper Bowling is useful in the space between lint and compile.

SwiftLint can tell you whether local Swift code follows style and convention. The compiler can tell you whether the program builds. Bumper Bowling asks a different question: does this change violate the project's architectural rules?

Examples:

- May the CLI import this module?
- Does each file have one architectural owner?
- Did this parser keep an enum-backed state machine?
- Did domain code introduce raw string identity, `Any`, broad existentials, or stored mutable state?
- Did an agent add a direct string comparison outside the matcher boundary?

Those are not formatting questions, and most are not compiler errors. They are codebase-shape questions.

## Agent Workflow

Bumper Bowling is designed for agentic coding loops:

1.  Declare the lanes and house rules in the DSL.
2.  Let an agent make a change.
3.  Run `bumper lint` from a hook/CI job, or run `BumperBowlingTesting` from the project test suite.
4.  Use the scorecard to see the observed graph fact, the declared lane, and the bumper that was touched.
5.  Repair the smallest thing: move the code, change the dependency, or intentionally update the house rules.

The goal is not to make agents timid. The goal is to give them fast, formal feedback when they cross an architectural boundary.

## What It Checks

0.1 rules:

- `forbidden_import`: disallow configured imports in linted source files.
- `subsystem_boundary`: require subsystem imports to match declared dependencies.
- `duplicate_ownership`: detect overlapping subsystem path ownership.
- `declared_dependency_cycle`: reject cycles in declared subsystem dependencies.
- `stored_properties`: enforce typed assertions over SwiftSyntax stored property facts.
- `syntax_constructs`: enforce typed assertions over SwiftSyntax construct facts, including conservative direct string matching detection.
- `public_declarations`: require or disallow configured public declarations in scoped source files.
- `enum_state_machine`: require parser files to declare an enum state machine.

The `stored_properties` rule is deliberately syntax-first in 0.1. It checks explicit stored-property type annotations for mutable stored properties, `Any`, `any ...`, and raw `String` in configured paths. It does not perform compiler-level type inference or full public API analysis. See [docs/MODELING_ASSERTIONS.md](docs/MODELING_ASSERTIONS.md) for an example of using these assertions without overlapping SwiftLint.

## Quick Start

```bash
swift test
swift run bumper init /tmp/BumperExample
swift run bumper lint /tmp/BumperExample
```

`bumper init` writes a runnable `BumperBowling.swift`. `bumper lint` loads that Swift file, evaluates the typed DSL, scans the repository, and exits nonzero only for `error` findings.

Security note: the CLI executes `BumperBowling.swift` as native Swift through SwiftPM. Treat that file as trusted code and do not run `bumper lint`, `scan`, `snapshot`, or `explain` in repositories whose configuration you have not reviewed.

In test suites, use `BumperBowlingTesting` with the same configuration value:

```swift
import BumperBowlingCore
import BumperBowlingTesting
import Testing

@Test
func architectureStaysInLane() async throws {
    let harness = BumperTestHarness(configuration: configuration.architectureConfiguration)

    for message in try await harness.errorMessages(root: projectRoot) {
        Issue.record(Comment(rawValue: message))
    }
}
```

## How We Test Ourselves

Bumper Bowling runs on Bumper Bowling.

The project house rules live in `Tests/BumperBowlingCoreTests/BumperProjectConfiguration.swift`. They say:

- `BumperBowlingCore` owns the core source.
- `BumperBowling` owns the CLI source.
- The CLI may depend on the core.
- The core may not depend on the CLI or test harness.
- Core code must not declare `bumperBowling` as a public symbol.
- Core string matching must go through `StringMatcher`.
- Source fact collection must stay normalized through the graph model.

`SelfLintTests` runs those rules through `BumperBowlingTesting`:

```swift
@Test
func bumperLintsItselfWithoutErrors() async throws {
    let harness = BumperTestHarness(configuration: BumperProjectConfiguration.configuration)

    for message in try await harness.errorMessages(root: root) {
        Issue.record(Comment(rawValue: message))
    }
}
```

That is the product test. It proves the testing interface can keep a real repo in its lane.

The CLI has its own frames too:

```bash
swift test --filter SelfLint
swift test --filter BumperCommands
swift run bumper lint .
```

The snapshot test checks that `bumper snapshot` is deterministic. If the architecture scorecard changes, the checked-in snapshot must change with it.

## Commands

```bash
bumper init [root]
bumper lint [root]
bumper scan [root]
bumper snapshot [root]
bumper explain <path>
```

`bumper init` writes a sample `BumperBowling.swift` file. The CLI executes that file through SwiftPM so the config remains real Swift.

Because the configuration is executable Swift, the CLI is intended for trusted repositories. Use the testing API when the configuration is already compiled into a trusted test target.

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
            DoesNot(Declare("bumperBowling"), severity: .error)
            Requires(
                .explicitDomainSurfaces,
                .typedIdentity,
                .immutableStoredState,
                severity: .warning
            )
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
        NoDirectStringMatching(
            .error,
            paths: ["Sources/BumperBowlingCore"],
            except: ["Sources/BumperBowlingCore/StringMatcher.swift"]
        )
    }
}
```

DSL constructors parse strings into typed values at the boundary. `Owns`, `MayDependOn`, `DoesNotDependOn`, `MayUse`, `DoesNotUse`, `Declare`, `Declares`, `ContainSyntax`, `Does`, `DoesNot`, `Requires`, `Disallows`, and `NoDirectStringMatching` compile down to typed graph assertions over parsed SwiftSyntax facts, not loose strings.

Name-like predicates use `StringMatcher`: `"Reducer"` is `.exact("Reducer")`, with `.contains`, `.prefix`, and `.suffix` available when a rule intentionally wants pattern matching. Direct string matching enforcement is syntax-first: Bumper Bowling can flag obvious string-like `==`, `!=`, `contains`, `hasPrefix`, and `hasSuffix` usage outside the matcher, but compiler integration would be required to prove every arbitrary expression is a `String`.

## Architecture

Bumper Bowling is SwiftSyntax-driven. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the system shape, [docs/SWIFTSYNTAX_SURFACE.md](docs/SWIFTSYNTAX_SURFACE.md) for the observable fact surface, and [docs/ARCHITECTURE_SNAPSHOT.md](docs/ARCHITECTURE_SNAPSHOT.md) for the generated commands, pipeline, and rule snapshots.

League rules are documented in [docs/DEFAULT_RULE_SETS.md](docs/DEFAULT_RULE_SETS.md), including passing and failing examples for each shipped default combination.

Swift is the only language surface in 0.1. SwiftSyntax and SwiftParser stay inside `SwiftFileParser`; Bumper Bowling wraps those facts with DSL assertions.

## Development

This package uses Swift 6 strict concurrency settings.

```bash
swift test
```

CI runs the Swift package tests, command scorecard tests, and the Bumper Bowling self-lint product test on macOS.

SwiftLint is intentionally adjacent. The repo includes `.swiftlint.yml`, but Bumper Bowling does not shell out to SwiftLint and is not a replacement for it.

The checked-in architecture snapshot is validated by product tests using the Bumper Bowling project configuration in `Tests/BumperBowlingCoreTests/BumperProjectConfiguration.swift`.

## Non-Goals For 0.1

- No JSON config.
- No plugin system.
- No generated accessors.
- No dynamic member lookup config trick.
- No autocorrect.
- No diff mode or baselines.
- No semantic analyzer.

## License

Apache License 2.0. See [LICENSE](LICENSE).

## Release

See [CHANGELOG.md](CHANGELOG.md) and [docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md).
