# Rule Authoring

Bumper Bowling does not ship a house architecture. It ships one open rule
engine, SwiftSyntax-observed facts, and typed composition points so each
repository can define its own architecture vocabulary.

Every rule — built-in or project-defined — is a `RuleDefinition` evaluated over
one immutable `RuleContext`, producing `RuleFailure` values that become
`RuleViolation`s in one `RuleReport`. There is no second engine, no registry,
and no separate diagnostic shape for project rules.

## The Ladder

Author a rule at the highest level that expresses it, and move down only when
the level above cannot:

1. **Architecture DSL** — components, ownership, dependencies, capabilities,
   and `Requires(...)` bundles inside `Architecture { ... }`. Most policy
   belongs here.
2. **Standard shapers** — prebuilt `Rules.*` factories for common ownership and
   traversal invariants. One call, typed arguments.
3. **Closure rules over typed facts** — `Rules.repository(...)` with memoized
   `FactProvider` values when the invariant is repo-specific but the facts are
   standard.
4. **Per-file syntax rules and typed queries** — `Rules.files(...)` and
   `SyntaxQuery` when the rule needs to inspect parsed syntax.
5. **Raw `SyntaxVisitor`** — `VisitorRule` when nothing above fits. This is a
   permanent escape hatch, not a deprecation lane.

## Terms

- `RuleDefinition`: one rule — identity (`RuleMetadata`), scope (`RuleScope`),
  and an `evaluate(in:)` over `RuleContext`.
- `RuleContext`: the immutable evaluation context: configuration, the
  parse-once `RepositorySyntax`, and the memoized fact cache.
- `RuleFailure`: one finding from a rule; rule metadata is attached by the
  engine to produce a `RuleViolation`.
- `RuleSet`: an ordered collection of rules built with a result builder.
- `FactProvider`: a typed, memoized derivation over the parsed repository.
- `RuleScope`: where a rule applies — `.repository`, `.under(path)`,
  `.component(id)`, `.files(paths)`, or any predicate.
- `ComponentShape` / `AssertionShape`: reusable bundles of component and
  repository policy for the architecture DSL.

## Standard Shaper Catalog

All shapers are static members of `Rules`, implemented only through the public
rule, fact, and query interfaces. Each accepts an optional `id:` and
`severity:`.

| Shaper | Asserts |
| --- | --- |
| `Rules.singleDeclaration(symbol:owner:)` | Exactly one declaration of the symbol, under the owner path. A configured owner with no files is a configuration error. |
| `Rules.constructionOwnership(symbol:allowed:)` | The type is constructed only inside the allowed scope. |
| `Rules.canonicalConstruction(symbol:owners:)` | Same check, spelled for canonical-value ownership. |
| `Rules.boundaryOnly(symbol:allowed:)` | Calls to the function occur only inside the boundary scope. |
| `Rules.noAlternateAliases(symbol:allowing:)` | No `typealias` re-exposes the symbol outside the allowing scope. |
| `Rules.canonicalTraversal(root:structuralCase:owners:)` | Recursive traversal of the type — direct or mutual, over locally dispatched calls — stays with its owners. |
| `Rules.singleNominalSpelling(suffix:owner:)` | Every nominal declaration named with the suffix lives in the owner scope, using typed declaration facts. |

```swift
Rules.singleDeclaration(
    symbol: NominalSymbol("AccessibilityTarget"),
    owner: try RelativePathPrefix("Sources/Plans")
)

Rules.canonicalTraversal(
    root: NominalSymbol("AccessibilityHierarchy"),
    structuralCase: EnumCaseSymbol("container"),
    owners: .under(try RelativePathPrefix("Sources/Traversal"))
)
```

## Closure Rules Over Typed Facts

`Rules.repository(_:severity:_:)` evaluates once over the whole repository.
Request facts through `context.facts(_:)`; providers are derived once per run
and memoized:

```swift
Rules.repository("project.no_uikit", severity: .error) { context in
    try context.facts(BuiltInFacts.imports).occurrences
        .filter { $0.module.rawValue == "UIKit" }
        .map { RuleFailure(path: $0.path, message: "UIKit is not allowed here.") }
}
```

Built-in providers under `BuiltInFacts`:

| Provider | Fact |
| --- | --- |
| `sourceFiles` | Projected per-file facts (imports, declarations, stored properties, constructs). |
| `imports` | Every import occurrence with module, path, and component. |
| `declarations` | Nominal declaration inventory with `occurrences(of:)` lookup. |
| `nominalTypes` | Typed nominal declarations with kind, access, inheritance, and location. |
| `extensions` | Extension declarations. |
| `storedProperties` | Stored properties with explicit types and mutability. |
| `syntaxNodes` | The observed syntax-node catalog. |
| `functionCalls` | Function and initializer calls with `calls(to:)` lookup. |
| `directRecursion` | Functions that call themselves. |
| `recursiveCallGroups` | Strongly connected components of the locally dispatched call graph — direct and mutual recursion; calls on another receiver never form edges. |
| `effectiveAccess` | Declared vs. effective access levels. |
| `enclosingDeclarations` | Each declaration's enclosing nominal chain. |
| `memberReferences` | Member accesses with optional base names. |
| `componentDependencies` | Component-to-component import edges. |

### Defining Your Own Fact Provider

A provider is a value type with a stable `id` and a `derive(in:)`:

```swift
struct DeclarationsPerFile: FactProvider {
    let id: FactProviderID = "project.declarations_per_file"

    func derive(in context: FactDerivationContext) throws -> [RelativeFilePath: Int] {
        let occurrences = try context.facts(BuiltInFacts.declarations).occurrences
        return Dictionary(grouping: occurrences, by: \.path).mapValues(\.count)
    }
}
```

Providers may request other providers through `context.facts(_:)`; cycles are
explicit errors, never deadlocks or empty results. Derivation failures fail the
run — an analysis error is never an empty match set.

## Per-File Syntax Rules and Typed Queries

`Rules.files(_:severity:_:)` runs once per parsed file. The whole run parses
each file exactly once; every rule shares the same trees.

Typed queries compose over the parsed file and preserve node types:

```swift
Rules.files("project.no_alternate_aliases") { file in
    typeAliases()
        .aliasing(NominalSymbol("AccessibilityTarget"))
        .matches(in: file)
        .map { match in
            match.failure(message: "\(match.node.name.text) aliases AccessibilityTarget.")
        }
}
```

Query roots: `functions()`, `initializers()`, `variables()`, `typeAliases()`,
`nominalDeclarations()`, `functionCalls()`. Capability-specific operations —
`taking(_:)`, `callingSelf()`, `aliasing(_:)`, `excluding(_:)` — narrow matches
while keeping the concrete SwiftSyntax node type, so `match.node` needs no
casting.

### Raw Visitor Escape Hatch

When nothing typed fits, walk the tree yourself:

```swift
import SwiftSyntax

final class ForceUnwrapCollector: SyntaxVisitor {
    private(set) var nodes: [ForceUnwrapExprSyntax] = []

    override func visit(_ node: ForceUnwrapExprSyntax) -> SyntaxVisitorContinueKind {
        nodes.append(node)
        return .skipChildren
    }
}

Rules.files("project.no_force_unwrap") { file in
    let visitor = ForceUnwrapCollector(viewMode: .sourceAccurate)
    visitor.walk(file.syntax)
    return visitor.nodes.map { node in
        file.failure(at: node, message: "Force unwrapping is not allowed here.")
    }
}
```

`SourceFileContext` exposes `path`, `component`, `source`, `syntax`,
`position(of:)`, `location(for:)`, and `failure(at:message:evidence:)`.

## Wiring Rules Into The Project

Project rules join built-ins in the `Rules` block of `BumperBowling.swift`:

```swift
let bumper = BumperProject {
    Architecture(AppComponent.self) {
        Component(.core) {
            Owns("Sources/Core")
            Modules("Core")
        }
    }

    Rules {
        DependencyBoundaries(.error)
        Rules.singleDeclaration(
            symbol: NominalSymbol("AccessibilityTarget"),
            owner: try! RelativePathPrefix("Sources/Core")
        )
        projectRules
    }
}
```

Rule IDs must be unique across built-in and project rules; a duplicate is a
configuration error. Rules evaluate sequentially in declaration order, and the
final report is sorted by path, line, column, rule ID, then message — so
declaration order never changes the report.

## Where To Define Vocabulary

Use the smallest placement that keeps the configuration readable.

### Inline

For one-off vocabulary, define values directly in `BumperBowling.swift`.

### Repo-Local `.bumper/Sources`

For vocabulary that belongs to one repository, put Swift files under
`.bumper/Sources`. Bumper Bowling compiles those files beside
`BumperBowling.swift` in the project runner:

```text
.bumper/
  Sources/
    ArchitectureVocabulary.swift
    ProjectRules.swift
BumperBowling.swift
```

```swift
// .bumper/Sources/ArchitectureVocabulary.swift
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

Repo-local `.bumper/Sources` files can import `SwiftSyntax` directly.

### Local SwiftPM Package

For vocabulary shared by multiple repositories, use a normal SwiftPM package at
`.bumper/Package.swift`. Bumper Bowling expects a `BumperRules` library product
and makes it importable from `BumperBowling.swift`. Importing a package never
applies rules by convention; the project still opts in explicitly inside
`Rules { ... }`. A packaged rule library must declare its own SwiftSyntax
dependency when it names AST types.

## Testing Rules

`BumperBowlingTestSupport` tests exactly one rule (or one `RuleSet`) in memory,
with no checkout and no filesystem, returning the same `RuleReport` the engine
and CLI produce:

```swift
import BumperBowlingCore
import BumperBowlingTestSupport
import Testing

@Test
func flagsForeignDeclarations() throws {
    let rule = Rules.singleDeclaration(
        symbol: NominalSymbol("AccessibilityTarget"),
        owner: try RelativePathPrefix("Sources/Plans")
    )

    let report = try RuleTestHarness(rule).evaluate(
        VirtualRepository {
            VirtualSourceFile.swift("Sources/Plans/Target.swift", component: "plans", source: "struct AccessibilityTarget {}")
            VirtualSourceFile.swift("Sources/Score/Foreign.swift", component: "score", source: "struct AccessibilityTarget {}")
        }
    )

    #expect(report.violations.map(\.path.rawValue) == ["Sources/Score/Foreign.swift"])
}
```

`VirtualSourceFile.swift(_:component:source:)` accepts strings, `ComponentID`,
or your project's `ComponentKey` enum. The harness is framework-neutral — it
works under Swift Testing and XCTest alike.

## Built-In DSL Primitives

Bumper Bowling includes a small set of reusable requirement values. Treat these
as primitives and examples, not as a canonical architecture.

Current stored-property requirements:

- `.noStoredProperties`
- `.immutableStoredState`
- `.noAnyStoredProperties`
- `.noBroadExistentialStoredProperties`
- `.noBoolStoredProperties`
- `.noOptionalStoredProperties`
- `.noRawStringStoredProperties`

Current semantic conveniences:

- `.explicitDomainSurfaces`: no `Any` or broad existential stored properties.
- `.typedIdentity`: no stored properties explicitly typed as `String`.
- `.computedState`: no stored properties.
- `.functionalCore`: no selected imperative constructs.
- `.swiftBasics`: `.explicitDomainSurfaces`, `.typedIdentity`, and
  `.immutableStoredState`.
- `.parserStateMachine`: requires enum state-machine evidence in scoped parser
  files.
- `.pureDomain`: `.swiftBasics` plus `.functionalCore`.

Current graph assertions:

- `DependencyBoundaries`
- `SingleOwner`
- `AcyclicDeclaredDependencies`

Current direct syntax helpers:

- `RequireSyntax(_:)`
- `DisallowSyntax(_:)`
- `ContainSyntax(_:)`
- `ContainSyntaxNode(_:)`
- `Disallows(_:)`
- `Does(_:)`
- `DoesNot(_:)`
- `Declares(_:)`

Use `ContainSyntaxNode(_:)` when a repository needs a fact Bumper Bowling does
not name as a built-in rule. `SyntaxNodeMatcher` can match by SwiftSyntax node
kind, spelling, parent kind, ancestor kind, or any combination.

## Boundary

Use SwiftLint for local style, formatting, and code-smell policy.

Use the Swift compiler for inferred types, symbol resolution, macro expansion,
protocol conformance truth, and build-target truth.

Use Bumper Bowling when the rule is about architecture policy and SwiftSyntax
can observe enough source facts to report deterministic evidence.

Every finding should be explainable as:

```text
observed source fact + declared scope = mismatch
```

If Bumper Bowling cannot show the observed fact, it should not report the
violation.

## Authoring Guidance

- Prefer positive vocabulary: `Requires(.domainCore)` is easier to review than
  scattered prohibitions.
- Author at the highest rung of the ladder that expresses the rule.
- Keep vocabulary repository-owned unless several repositories actually share
  it.
- Start narrow. Scope stricter requirements to paths that are already clean or
  intentionally being cleaned.
- Use warning severity for migration lanes and error severity for contracts CI
  should enforce.
- Do not encode SwiftLint rules as Bumper rules.
- Do not encode compiler questions as SwiftSyntax rules.
- Do not add generated accessors, registries, remote package policy, JSON
  configuration, or auto-loaded rules.
