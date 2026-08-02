# Rule Factories

[Built-ins index](README.md)

These factories turn repository code into `RuleDefinition` values.

| Factory | Evaluation |
| --- | --- |
| `Rules.repository` | Runs once with a `RuleContext`. |
| `Rules.files` | Runs once for each parsed file in scope. |
| `Rules.assert` | Applies a per-file cardinality to a `SyntaxPattern`. |
| `Rules.forbid` | Reports every match from a `SyntaxPattern`. |
| `Rules.visitor` | Runs a raw `SyntaxVisitor` and collects its failures. |

## Repository Rule

```swift
Rules.repository(
    "project.no_uikit",
    summary: "The repository does not import UIKit."
) { context in
    try context.facts(BuiltInFacts.imports).occurrences
        .filter { $0.module.rawValue == "UIKit" }
        .map {
            RuleFailure(
                path: $0.path,
                message: "UIKit is not allowed here."
            )
        }
}
```

## File Rule

```swift
Rules.files(
    "project.no_target_aliases",
    summary: "Target has one spelling."
) { file in
    typeAliases()
        .aliasing("Target")
        .matches(in: file)
        .map { $0.failure(message: "Target has an alternate alias.") }
}
```

## Cardinality Rule

```swift
Rules.assert(
    functions().named("reduce"),
    cardinality: .exactly(1),
    id: "feature.one_reducer",
    summary: "Each feature file declares one reducer.",
    scope: .under("Sources/Features")
)
```

Available cardinalities are `.none`, `.atLeast(_)`, `.atMost(_)`, and
`.exactly(_)`.

## Forbidden Pattern

```swift
Rules.forbid(
    typeAliases().aliasing("UserID"),
    id: "identity.one_spelling",
    summary: "UserID has one spelling.",
    message: { match in
        "\(match.node.name.text) aliases UserID."
    }
)
```

## Raw Visitor

```swift
Rules.visitor(
    "project.no_force_unwrap",
    summary: "Production code handles optional absence.",
    scope: .productionSources
) { file in
    ForceUnwrapVisitor(file: file)
}
```

The visitor conforms to `SyntaxVisitor` and `RuleFailureSource`.

Next: [Syntax queries](syntax-queries.md)
