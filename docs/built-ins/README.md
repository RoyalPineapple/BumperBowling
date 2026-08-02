# Built-In Rule Authoring Catalog

This catalog covers the built-in pieces for writing Bumper Bowling policy.
Each page starts with a high-level convenience and shows its lower-level parts.

The configuration is Swift. A repository can compose these values, define new
values, or use the public SwiftSyntax layer directly.

## Choose A Level

| Policy need | Built-in surface | Reference |
| --- | --- | --- |
| Describe a component | Component elements and `ComponentShape` | [Components](components.md) |
| Reuse source requirements | `ComponentRequirement` | [Requirements](requirements.md) |
| Validate the component graph | Graph assertions and `AssertionShape` | [Assertions](assertions.md) |
| Apply a common repository rule | Standard `Rules.*` shapers | [Standard shapers](shapers.md) |
| Create a repository rule | Rule factories and `RuleDefinition` | [Rule factories](rule-factories.md) |
| Match syntax in each file | `SyntaxQuery` and typed syntax views | [Syntax queries](syntax-queries.md) |
| Select files and syntax nodes | Scopes, matching, and severity | [Scopes and matching](scopes-and-matching.md) |
| Evaluate typed repository facts | `Rules.repository` and `BuiltInFacts` | [Facts](facts.md) |

All levels produce the same `RuleFailure` and `RuleReport` values.

## How The Pieces Fit

```text
SwiftSyntax
    -> SyntaxQuery and BumperSyntaxView
    -> built-in or repository-defined facts
    -> RuleDefinition
    -> RuleSet
    -> BumperProject Rules block
    -> RuleReport with source evidence
```

The high-level conveniences use this same path. They add names and composition,
not another evaluator.

Read [Build An Architecture Rule From The Ground Up](../RULE_FROM_THE_GROUND_UP.md)
for one complete example.
