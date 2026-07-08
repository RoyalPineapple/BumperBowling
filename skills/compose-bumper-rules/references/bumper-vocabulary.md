# Bumper Vocabulary

## Terms

- `ComponentRequirement`: a reusable set of source-fact rules.
- `ComponentShape`: a reusable bundle of component DSL elements.
- `AssertionShape`: a reusable bundle of repo-level rule configuration.
- `RuleConfiguration`: the evaluated/scoped policy Bumper Bowling runs.
- `Scope`: paths, components, or exclusions where a rule applies.

## Core Pattern

```swift
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
        DoesNotUse(.uiKit, .swiftUI)
        Requires(.domainCore, severity: .error)
        DoesNot(
            ContainSyntaxNode(
                SyntaxNodeMatcher(
                    kind: .attribute,
                    spelling: .exact("available")
                )
            ),
            severity: .warning
        )
    }
}

extension AssertionShape {
    static let global = AssertionShape {
        DependencyBoundaries(.error)
        SingleOwner(.error)
        AcyclicDeclaredDependencies(.error)
    }
}
```

Then apply it:

```swift
let configuration = BumperConfiguration {
    Architecture {
        Component(.core) {
            Owns("Sources/Core")
            Applies(.domain)
        }
    }

    Assertions {
        ApplyAssertions(.global)
    }
}
```

## Syntax Node Predicates

Use `ContainSyntax(_:)` when only SwiftSyntax kind membership matters:

```swift
DoesNot(ContainSyntax(.forceUnwrapExpr), severity: .error)
```

Use `ContainSyntaxNode(_:)` when the repo needs policy Bumper Bowling does not
name as a built-in requirement:

```swift
DoesNot(
    ContainSyntaxNode(
        SyntaxNodeMatcher(
            kind: .attribute,
            spelling: .exact("available")
        )
    ),
    severity: .warning
)
```

`SyntaxNodeMatcher` composes with SwiftSyntax instead of duplicating it:

- `kind`: `SyntaxKind`, such as `.attribute` or `.structDecl`
- `spelling`: `StringMatcher`, such as `.exact("available")`
- `parentKind`: immediate parent `SyntaxKind`
- `ancestorKind`: any recorded ancestor `SyntaxKind`

Do not use or invent `family`, `nodeKind`, `SyntaxFact`, or JSON rule schemas.

## Guardrails

- Do not promise facts SwiftSyntax cannot observe.
- Do not auto-apply rules from a package. Importing only makes values available.
- Do not make consumer vocabulary sound canonical for every repo.
- Prefer one clear shape over many tiny speculative shapes.
- Prefer generic syntax node predicates over upstreaming repo-specific named
  rules.
