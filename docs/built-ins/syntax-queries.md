# Syntax Queries

[Built-ins index](README.md)

Every query returns typed `SyntaxMatch` values. `match.node` retains its
concrete SwiftSyntax node type.

## Query Roots

| Query | Match type |
| --- | --- |
| `functions()` | `FunctionDeclSyntax` |
| `initializers()` | `InitializerDeclSyntax` |
| `variables()` | `VariableDeclSyntax` |
| `typeAliases()` | `TypeAliasDeclSyntax` |
| `nominalDeclarations()` | Nominal `DeclSyntax` values |
| `functionCalls()` | `FunctionCallExprSyntax` |
| `SyntaxQuery<Node>()` | Any selected SwiftSyntax node type |

## Query Composition

| Operation | Result |
| --- | --- |
| `.filter { ... }` | Keeps matches that meet a predicate. |
| `.compactMap { ... }` | Changes the match node type. |
| `.within(ruleScope)` | Includes files in a `RuleScope`. |
| `.excluding(ruleScope)` | Excludes files in a `RuleScope`. |
| `.lexically(within: syntaxScope)` | Includes nodes in a `SyntaxScope`. |
| `.lexically(excluding: syntaxScope)` | Excludes nodes in a `SyntaxScope`. |

Typed capabilities add these operations:

| Query | Operation | Match |
| --- | --- | --- |
| `functions()` | `.named(_:)` | Functions with a matching base name. |
| `functions()` | `.taking(_:)` | Functions with a matching explicit parameter type. |
| `functions()` | `.callingSelf()` | Direct self-recursive functions. |
| `typeAliases()` | `.aliasing(_:)` | Aliases with a matching explicit target spelling. |

`BumperSyntaxView` adds value-only syntax facts. Important views include:

- Variable binding names, mutability, membership, and explicit types
- `TypeShape` names, function shape, and attributes
- Lexical placement and enclosing declarations
- Typealias target shape
- Function-call spelling

Read [the SwiftSyntax surface](../SWIFTSYNTAX_SURFACE.md) for the complete syntax
contract.

Next: [Scopes, matching, and severity](scopes-and-matching.md)
