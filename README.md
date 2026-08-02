# Bumper Bowling

[![CI](https://github.com/RoyalPineapple/BumperBowling/actions/workflows/ci.yml/badge.svg)](https://github.com/RoyalPineapple/BumperBowling/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/RoyalPineapple/BumperBowling)](https://github.com/RoyalPineapple/BumperBowling/releases/latest)
[![License](https://img.shields.io/github/license/RoyalPineapple/BumperBowling)](LICENSE)

**Turn your Swift repository's unwritten rules into rules everyone can run.**

Your team knows that every SwiftUI screen needs a preview. Then a new screen
arrives without one:

```swift
struct CheckoutView: View {
    var body: some View {
        CheckoutForm()
    }
}
```

The compiler accepts it. Bumper Bowling applies the repository's rule:

```swift
import BumperBowlingCore
import SwiftSyntax

let swiftUIPreviews = Rules.files(
    "app.swiftui_preview",
    summary: "Each SwiftUI view is constructed by at least one preview.",
    scope: .under("Sources/Features")
) { file in
    let views = structs().inheriting("View").matches(in: file)

    let previews = macroExpansions().named("Preview").matches(in: file)

    return views.compactMap { view in
        let viewName = view.node.name.text
        let hasMatchingPreview = previews.contains { preview in
            let constructedTypes = preview.node
                .descendants(of: FunctionCallExprSyntax.self)
                .map(\.calleeName)

            return constructedTypes.contains(viewName)
        }

        guard hasMatchingPreview else {
            return view.failure(
                message: "\(viewName) needs a #Preview that constructs \(viewName)."
            )
        }

        return nil
    }
}
```

Now the same omission produces source evidence:

```text
Sources/Features/Checkout/CheckoutView.swift:1:1
CheckoutView needs a #Preview that constructs CheckoutView. (app.swiftui_preview)
```

That rule is ordinary Swift over typed SwiftSyntax nodes. Keep it local, give
it a project name, or compose it with larger architecture policy.

## Describe The Shape Of Your App

A screen preview is one rule. A feature can have a complete architectural
shape:

```swift
extension ComponentRequirement {
    static let featureState = ComponentRequirement(
        .explicitDomainSurfaces,
        .typedIdentity,
        .immutableStoredState
    )
}

extension ComponentShape {
    static let feature = ComponentShape {
        MayUse(.foundation, .swiftUI)
        Requires(.featureState)
        Declares("State", "Action", "View")
    }
}
```

Apply that shape to real parts of the app:

```swift
enum AppComponent: String, ComponentKey {
    case domain
    case catalog
    case checkout
    case app
}

Architecture(AppComponent.self) {
    Component(.domain) {
        Owns("Sources/Domain")
        Modules("Domain")
        MayUse(.foundation)
        Requires(.pureDomain)
    }

    Component(.catalog) {
        Owns("Sources/Features/Catalog")
        Modules("CatalogFeature")
        MayDependOn(.domain)
        Applies(.feature)
    }

    Component(.checkout) {
        Owns("Sources/Features/Checkout")
        Modules("CheckoutFeature")
        MayDependOn(.domain, .catalog)
        Applies(.feature)
    }

    Component(.app) {
        Owns("Sources/App")
        Modules("App")
        MayDependOn(.domain, .catalog, .checkout)
        MayUse(.foundation, .swiftUI, .networking)
    }
}
```

The declaration now carries facts that previously lived in code review:

- Catalog and Checkout use the same feature shape.
- Each feature declares `State`, `Action`, and `View`.
- Feature state uses explicit types, typed identities, and immutable stored properties.
- Catalog can depend on Domain.
- Checkout can depend on Domain and Catalog.
- App can assemble Domain, Catalog, and Checkout.
- Networking belongs to App.

Add graph rules to enforce the declared relationships:

```swift
Rules {
    DependencyBoundaries(.error)
    SingleOwner(.error)
    AcyclicDeclaredDependencies(.error)
    swiftUIPreviews
}
```

A forbidden import, an unowned file, a dependency cycle, or a missing preview
now produces the same structured report.

## Enforce Patterns Across The Repository

Architecture also appears in construction, ownership, and control flow.
Bumper Bowling includes composable rules for these patterns.

Keep live service construction at the composition root:

```swift
Rules.canonicalConstruction(
    "AppEnvironment",
    owners: .under("Sources/App/Bootstrap")
)
```

Keep decoding at the repository's decoding boundary:

```swift
Rules.boundaryOnly(
    function: "JSONDecoder.decode",
    allowed: .under("Sources/Infrastructure/Decoding")
)
```

Give a canonical type one spelling:

```swift
Rules.noAlternateAliases(
    "UserID",
    allowing: .under("Sources/Migrations")
)
```

Keep recursive tree traversal with its owner:

```swift
Rules.canonicalTraversal(
    root: "RouteTree",
    structuralCase: "branch",
    owners: .under("Sources/Navigation/Traversal")
)
```

Require one reducer in each feature file:

```swift
Rules.assert(
    functions().named("reduce"),
    cardinality: .exactly(1),
    id: "app.feature_reducer",
    summary: "Each feature file declares one reducer.",
    scope: .under("Sources/Features")
)
```

These rules combine declarations, types, imports, calls, paths, syntax scopes,
and repository-wide facts. Swift supplies the composition language. SwiftSyntax
supplies the source model. Bumper Bowling supplies the rule engine, scopes,
tests, and reports.

```text
SwiftSyntax -> typed observations -> scopes -> rules -> source evidence
```

**Bumper Bowling makes SwiftSyntax practical for enforcing the truths that
define your codebase.**

## Start With A Built-In Or Drop Down

Use the highest level that expresses the rule clearly:

| Rule | Building piece |
| --- | --- |
| Component ownership and dependencies | Architecture DSL |
| A reusable feature or domain shape | `ComponentRequirement` and `ComponentShape` |
| Common ownership and construction patterns | `Rules.*` shapers |
| A typed syntax pattern | `SyntaxQuery`, `Rules.assert`, and `Rules.forbid` |
| A rule over each parsed file | `Rules.files` |
| A rule over repository-wide facts | `BuiltInFacts` and `Rules.repository` |
| A specialized source walk | `Rules.visitor` and `SyntaxVisitor` |

All levels use the same parsed files, rule protocol, scopes, and report. A
repository can mix them in one `Rules` block.

The repository owns the vocabulary. Names such as `.feature`,
`.featureState`, and `app.swiftui_preview` stay beside the code that gives them
meaning. Shared vocabulary can live in a local Swift package with a
`BumperRules` library product.

Read the [built-in catalog](docs/built-ins/README.md) for every included piece.
Read [rule authoring](docs/RULE_AUTHORING.md) for custom facts, queries,
visitors, and fixtures. The [ground-up rule guide](docs/RULE_FROM_THE_GROUND_UP.md)
shows how recursive calls become one architecture rule.

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

A complete configuration is a Swift program:

```swift
import BumperBowlingCore

enum AppComponent: String, ComponentKey {
    case domain
    case features
    case app
}

let bumper = BumperProject {
    Included { "Sources" }

    Architecture(AppComponent.self) {
        Component(.domain) {
            Owns("Sources/Domain")
            Modules("Domain")
            MayUse(.foundation)
            Requires(.pureDomain)
        }

        Component(.features) {
            Owns("Sources/Features")
            Modules("Features")
            MayDependOn(.domain)
            MayUse(.foundation, .swiftUI)
        }

        Component(.app) {
            Owns("Sources/App")
            Modules("App")
            MayDependOn(.domain, .features)
            MayUse(.foundation, .swiftUI, .networking)
        }
    }

    Rules {
        DependencyBoundaries(.error)
        SingleOwner(.error)
        AcyclicDeclaredDependencies(.error)

        Rules.canonicalConstruction(
            "AppEnvironment",
            owners: .under("Sources/App/Bootstrap")
        )
    }
}
```

Keep repository-specific values in `.bumper/Sources`:

```text
.bumper/
  Sources/
    ArchitectureVocabulary.swift
    ProjectRules.swift
BumperBowling.swift
```

`BumperBowling.swift` applies each value explicitly. Importing a file makes its
Swift values available to the configuration.

## Put The Bumpers In CI

Your team declares the lanes. A developer or agent takes the shot. CI catches
a wild change before merge and points it back toward the declared architecture.

Run the same command locally and in CI:

```bash
swift run bumper lint .
```

Use a baseline for an advisory rollout:

```bash
swift run bumper lint . --format json --fail-on none
swift run bumper baseline create . --output .bumper-baseline.json
swift run bumper lint . --baseline .bumper-baseline.json --fail-on error
```

Test repository rules with focused source fixtures:

```bash
swift run bumper test .
```

This repository validates itself through the same public API.

## Keep Agents In The Same Lane

An agent can read the architecture before it edits a file. After the edit, the
agent runs the same rules as the developer and CI. A finding includes the rule,
file, location, observed fact, and expected fact.

When the architecture changes, the agent can update its vocabulary, rules, and
fixtures with the source change. Review then shows the new architecture and the
code that uses it together.

The repository includes a Codex skill for this workflow:

```text
skills/compose-bumper-rules/
```

Install the skill from the Bumper Bowling repository root:

```bash
mkdir -p "${CODEX_HOME:-$HOME/.codex}/skills"
ln -s "$PWD/skills/compose-bumper-rules" \
  "${CODEX_HOME:-$HOME/.codex}/skills/compose-bumper-rules"
```

Start a new Codex session. Then invoke `$compose-bumper-rules`, or ask Codex to
create, review, or revise Bumper Bowling policy.

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

The `bumper` process scans the repository. The runner parses each selected file
once and shares the syntax trees across rules. An unchanged configuration uses
the cached runner.

By default, the runner uses a release build. Use
`BUMPER_RUNNER_BUILD_CONFIGURATION=debug` on a smaller CI host to reduce the
initial build time.

Use `BUMPER_CACHE_DIR` to persist the runner cache in CI:

```bash
BUMPER_CACHE_DIR=.build/bumper-cache swift run bumper lint .
```

Evaluation has a 60-second default limit. Set
`BUMPER_EVALUATION_TIMEOUT_SECONDS` to a positive number of seconds for a
larger repository.

## Development

```bash
BUMPER_RUNNER_BUILD_CONFIGURATION=debug swift test
swift run bumper lint .
```

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
