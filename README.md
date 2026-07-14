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

SwiftPM is the canonical distribution path for Bumper Bowling. Use the package
directly from this repository, pinned to a release tag:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/RoyalPineapple/BumperBowling.git", from: "0.5.1")
]
```

The package exposes:

- `BumperBowlingCore` for Swift configuration and test integration.
- `bumper` for command-line linting through `swift run`.

```bash
swift run bumper init .
swift run bumper lint .
```

`bumper init` writes a starter `BumperBowling.swift`. `bumper lint` loads it,
scans the repo, and exits nonzero for `error` findings.

For CI rollouts, Bumper Bowling can emit JSON, run advisory, and compare against
a checked-in baseline:

```bash
swift run bumper lint . --format json --fail-on none
swift run bumper baseline create . --output .bumper-baseline.json
swift run bumper lint . --baseline .bumper-baseline.json --fail-on error
```

## Configuration

`BumperBowling.swift` declares one `BumperProject` named `bumper`. Component
names come from your own `ComponentKey` enum, so `Component(.core)` and
`MayDependOn(.core)` are typo-checked by the compiler:

```swift
import BumperBowlingCore

enum AppComponent: String, ComponentKey {
    case core
    case cli
}

let bumper = BumperProject {
    Included {
        "Sources"
    }

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

The same architecture works in your test suite, so architecture failures are
just test failures:

```swift
import BumperBowlingCore
import Testing

@Test
func architectureStaysInLane() async throws {
    let report = try await BumperCommands.lint(
        root: projectRoot,
        configuration: bumper.architecture
    )

    for violation in report.violations where violation.severity == .error {
        let message = "\(violation.path.rawValue): \(violation.message)"
        Issue.record(Comment(rawValue: message))
    }
}
```

The DSL reference lives in the [configuration language spec](docs/DSL_SPEC.md).
Rule-authoring guidance and examples live in
[rule authoring](docs/RULE_AUTHORING.md).

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

## Project Rules

When a repository needs a rule Bumper Bowling cannot know in advance, define it
as an ordinary `RuleDefinition` and add it to the project's `Rules` block. Built-in
rules and project rules run in one engine and produce one `RuleReport`.

Fact-based rules evaluate memoized typed facts over the parsed repository:

```swift
// .bumper/Sources/ProjectRules.swift
import BumperBowlingCore

let projectRules = RuleSet {
    Rules.repository("the_score.import_allow_list", severity: .error) { context in
        let allowedImports = Set(["Foundation"])
        return try context.facts(BuiltInFacts.imports).occurrences
            .filter { !allowedImports.contains($0.module.rawValue) }
            .map { occurrence in
                RuleFailure(
                    path: occurrence.path,
                    message: "\(occurrence.component.rawValue) imports non-allowlisted module \(occurrence.module.rawValue)",
                    evidence: ViolationEvidence(
                        observed: occurrence.module.rawValue,
                        expectation: "allowed imports: Foundation"
                    )
                )
            }
    }
}
```

```swift
// BumperBowling.swift
Rules {
    DependencyBoundaries(.error)
    projectRules
}
```

When projected facts are not enough, write a per-file syntax rule. Each rule
receives a `SourceFileContext` with the parsed `SourceFileSyntax`, source text,
component metadata, and location helpers — every file is parsed exactly once
per run, shared across all rules:

```swift
import BumperBowlingCore
import SwiftSyntax

let projectRules = RuleSet {
    Rules.files("core.no_tuple_api", severity: .error) { file in
        let visitor = TupleTypeCollector(viewMode: .sourceAccurate)
        visitor.walk(file.syntax)

        return visitor.tuples.map { tuple in
            file.failure(
                at: tuple,
                message: "Tuple API must use a named type.",
                evidence: ViolationEvidence(
                    observed: tuple.trimmedDescription,
                    expectation: "named type"
                )
            )
        }
    }
}

private final class TupleTypeCollector: SyntaxVisitor {
    private(set) var tuples: [TupleTypeSyntax] = []

    override func visit(_ node: TupleTypeSyntax) -> SyntaxVisitorContinueKind {
        tuples.append(node)
        return .skipChildren
    }
}
```

Common ownership and traversal invariants ship as prebuilt shapers —
`Rules.singleDeclaration`, `Rules.constructionOwnership`, `Rules.boundaryOnly`,
`Rules.noAlternateAliases`, `Rules.canonicalTraversal`,
`Rules.canonicalConstruction`, and `Rules.singleNominalSpelling` — implemented
only through the same public rule, fact, and query interfaces.

Every rule can be tested in memory with `BumperBowlingTestSupport`:

```swift
import BumperBowlingTestSupport

let report = try RuleTestHarness(rule).evaluate(
    VirtualRepository {
        VirtualSourceFile.swift("Sources/Core/Thing.swift", component: "core", source: "struct Thing {}")
    }
)
```

See [rule authoring](docs/RULE_AUTHORING.md) for the full ladder: DSL, shapers,
typed facts and queries, and the raw `SyntaxVisitor` escape hatch.

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
bumper init [root]             # write a starter configuration
bumper lint [root]             # check the repo against it
bumper scan [root]             # show the architecture graph the code expresses
bumper baseline create [root]  # write a JSON baseline for current violations
bumper snapshot [root]         # render the configured architecture
bumper config [root]           # how your configuration loads, and whether it is valid
bumper explain <path>          # what bumper sees in one file
```

`lint` and `scan` accept `--format markdown|json`. `lint` also accepts
`--fail-on none|note|warning|error`, `--baseline <path>`, and `--progress`.
Use `BUMPER_CACHE_DIR` to put compiled configuration and custom rule runners in
a stable CI cache location.

## How The Configuration Loads

`BumperBowling.swift` is a program, not a data file — the same as
`Package.swift`. So Bumper Bowling loads it the way SwiftPM loads a manifest:
it compiles the file into one cached project runner and runs that runner in a
sealed-off process.

The runner has two modes. `describe` prints the architecture configuration as
JSON so the host knows what to scan. `evaluate` receives the scanned source
files as JSON on stdin, parses each file once, evaluates built-in and project
rules in one engine, and prints one `RuleReport` as JSON. The sealed-off
process has no network, nowhere to write, and an empty environment; scanning
stays in the `bumper` process itself.

The compile is cached against the file's contents, so it happens once per
change to `BumperBowling.swift`, not once per lint. An unchanged
configuration loads from cache with no build at all.

By default that cache lives under the system temporary directory. Set
`BUMPER_CACHE_DIR` when CI should persist it between runs:

```bash
BUMPER_CACHE_DIR=.build/bumper-cache swift run bumper lint .
```

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

The repo lints itself; that is the main product test. Releases are SwiftPM tags
from this repository. The checked-in architecture snapshot is generated by
`bumper snapshot`.

## Docs

- [Architecture](docs/ARCHITECTURE.md)
- [Configuration language](docs/DSL_SPEC.md)
- [Rule authoring](docs/RULE_AUTHORING.md)
- [Migrating to 0.5](docs/MIGRATION_0.5.md)
- [SwiftSyntax surface](docs/SWIFTSYNTAX_SURFACE.md)
- [Release checklist](docs/RELEASE_CHECKLIST.md)

## License

Apache License 2.0. See [LICENSE](LICENSE).
