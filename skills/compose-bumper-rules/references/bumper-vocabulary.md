# Bumper Bowling 0.5.2 Vocabulary

## Contents

- [Core Types](#core-types)
- [Architecture DSL](#architecture-dsl)
- [Standard Rules Shapers](#standard-rules-shapers)
- [Typed Facts](#typed-facts)
- [Typed Queries And Per-File Rules](#typed-queries-and-per-file-rules)
- [Raw Visitor Escape Hatch](#raw-visitor-escape-hatch)

## Core Types

- `RuleDefinition`: metadata, scope, and `evaluate(in:)`.
- `RuleContext`: immutable configuration, parse-once repository syntax, and
  memoized facts.
- `RuleFailure`: one project-rule finding; the engine attaches metadata to
  produce a `RuleViolation` in a `RuleReport`.
- `RuleSet`: ordered `RuleDefinition` values.
- `FactProvider`: typed, memoized repository derivation.
- `RuleScope`: `.repository`, `.under(path)`, `.component(id)`,
  `.files(paths)`, or a predicate.
- `ComponentShape` / `AssertionShape`: reusable Architecture DSL policy.

## Architecture DSL

```swift
import BumperBowlingCore

enum AppComponent: String, ComponentKey {
    case core
}

let bumper = BumperProject {
    Architecture(AppComponent.self) {
        Component(.core) {
            Owns("Sources/Core")
            Modules("Core")
            MayUse(.foundation)
            Requires(.immutableStoredState, severity: .error)
        }
    }

    Rules {
        DependencyBoundaries(.error)
        Rules.singleDeclaration("AppModel", owner: "Sources/Core")
    }
}
```

## Standard `Rules` Shapers

Prefer these before writing a closure rule. Each accepts optional `id:` and
`severity:` arguments.

| Shaper | Purpose |
| --- | --- |
| `Rules.singleDeclaration(_:owner:)` | One declaration under its owner path. |
| `Rules.constructionOwnership(_:allowed:)` | Construction only in the allowed scope. |
| `Rules.canonicalConstruction(_:owners:)` | Canonical-value construction ownership. |
| `Rules.boundaryOnly(function:allowed:)` | Function calls only in a boundary scope. |
| `Rules.noAlternateAliases(_:allowing:)` | No aliases outside the allowing scope. |
| `Rules.canonicalTraversal(root:structuralCase:owners:)` | Recursive traversal stays with its owners. |
| `Rules.singleNominalSpelling(suffix:owner:)` | Suffixed nominal declarations stay under one owner. |

Symbols and paths are typed values with string-literal authoring:

```swift
Rules.canonicalTraversal(
    root: "AccessibilityHierarchy",
    structuralCase: "container",
    owners: .under("Sources/Traversal")
)
```

## Typed Facts

Use `Rules.repository(_:severity:summary:_:)`. Request facts with
`context.facts(_:)`; providers derive at most once per evaluation.

```swift
Rules.repository(
    "project.no_uikit",
    severity: .error,
    summary: "UIKit imports stay at the application boundary."
) { context in
    try context.facts(BuiltInFacts.imports).occurrences
        .filter { $0.module.rawValue == "UIKit" }
        .map {
            RuleFailure(path: $0.path, message: "UIKit is not allowed here.")
        }
}
```

Current `BuiltInFacts` providers:

- `sourceFiles`, `imports`, `declarations`, `nominalTypes`, `extensions`
- `storedProperties`, `syntaxNodes`, `functionCalls`, `directRecursion`
- `recursiveCallGroups`, `effectiveAccess`, `enclosingDeclarations`
- `memberReferences`, `componentDependencies`

Define a provider only when no built-in provider or composition supplies the
fact:

```swift
struct DeclarationsPerFile: FactProvider {
    let id: FactProviderID = "project.declarations_per_file"

    func derive(in context: FactDerivationContext) throws
        -> [RelativeFilePath: Int] {
        let occurrences = try context.facts(BuiltInFacts.declarations).occurrences
        return Dictionary(grouping: occurrences, by: \.path).mapValues(\.count)
    }
}
```

## Typed Queries And Per-File Rules

`Rules.files(_:severity:summary:_:)` evaluates each selected parsed file. Query roots
are `functions()`, `initializers()`, `variables()`, `typeAliases()`,
`nominalDeclarations()`, and `functionCalls()`.

```swift
Rules.files(
    "project.no_target_alias",
    summary: "AccessibilityTarget has one spelling."
) { file in
    typeAliases()
        .aliasing(NominalSymbol("AccessibilityTarget"))
        .matches(in: file)
        .map { match in
            match.failure(message: "AccessibilityTarget must not be aliased.")
        }
}
```

Use query operations such as `taking(_:)`, `callingSelf()`, `aliasing(_:)`, and
`excluding(_:)` to retain the concrete SwiftSyntax node type.

## Raw Visitor Escape Hatch

Use `Rules.visitor(...)` when the visitor owns arbitrary analysis and failure
collection. The visitor must conform to `RuleFailureSource`.

```swift
import SwiftSyntax

let noForceUnwrap = Rules.visitor(
    "project.no_force_unwrap",
    severity: .error,
    scope: .under("Sources"),
    summary: "Production code handles optional absence explicitly."
) { file in
    ForceUnwrapVisitor(file: file)
}

final class ForceUnwrapVisitor: SyntaxVisitor, RuleFailureSource {
    private let file: SourceFileContext
    private(set) var failures: [RuleFailure] = []

    init(file: SourceFileContext) {
        self.file = file
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(
        _ node: ForceUnwrapExprSyntax
    ) -> SyntaxVisitorContinueKind {
        failures.append(
            file.failure(at: node, message: "Force unwrap is not allowed.")
        )
        return .visitChildren
    }
}
```

`VisitorRule` is the concrete rule type returned by this factory. Raw visitors
remain supported; the escalation gate controls when to use them.
