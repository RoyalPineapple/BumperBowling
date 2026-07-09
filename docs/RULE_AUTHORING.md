# Rule Authoring

Bumper Bowling does not ship a house architecture. It ships a small Swift DSL,
SwiftSyntax-observed facts, and typed composition points so each repository can
define its own architecture vocabulary.

The core model is:

```text
SourceFactRule -> ComponentRequirement -> scoped Requires(...) -> finding
ComponentShape -> Applies(...) -> component policy
AssertionShape -> ApplyAssertions(...) -> repository policy
```

## Terms

- `SourceFactRule`: an atomic fact-level rule Bumper Bowling can evaluate from
  SwiftSyntax-observed source facts.
- `ComponentRequirement`: a reusable bundle of `SourceFactRule` values.
- `ComponentShape`: a reusable bundle of component policy, such as capabilities,
  dependency policy, and requirements.
- `AssertionShape`: a reusable bundle of repository-level assertions.
- `RuleConfiguration`: evaluated policy after a configuration scopes it.
- Scope: the paths, components, or exclusions where policy applies.

Shapes are vocabulary. Scopes are where that vocabulary applies.

Each scoped clause remains its own rule setting after composition. A shape can
make one requirement an error and another requirement a warning, or apply two
requirements to different paths, without those settings bleeding into each
other. The compatibility summary on `RuleConfiguration` still shows the merged
view for diagnostics and tests, but linting evaluates the scoped settings.

## Where To Define Vocabulary

Use the smallest placement that keeps the configuration readable.

### Inline

For one-off vocabulary, define values directly in `BumperBowling.swift`:

```swift
import BumperBowlingCore

extension ComponentRequirement {
    static let domainCore = ComponentRequirement(
        .explicitDomainSurfaces,
        .typedIdentity,
        .immutableStoredState
    )
}
```

### Repo-Local `.bumper/Sources`

For vocabulary that belongs to one repository, put Swift files under
`.bumper/Sources`. Bumper Bowling compiles those files beside
`BumperBowling.swift` in the configuration runner.

```text
.bumper/
  Sources/
    ArchitectureVocabulary.swift
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

extension AssertionShape {
    static let repoShape = AssertionShape {
        DependencyBoundaries(.error)
        SingleOwner(.error)
        AcyclicDeclaredDependencies(.error)
    }
}
```

```swift
// BumperBowling.swift
import BumperBowlingCore

let configuration = BumperConfiguration {
    Architecture {
        Component(.core) {
            Owns("Sources/Core")
            Modules("Core")
            Applies(.domain)
        }
    }

    Assertions {
        ApplyAssertions(.repoShape)
    }
}
```

### Local SwiftPM Package

For vocabulary shared by multiple repositories, use a normal SwiftPM package at
`.bumper/Package.swift`. Bumper Bowling expects a `BumperRules` library product
and makes it importable from `BumperBowling.swift`.

```text
.bumper/
  Package.swift
  Sources/
    BumperRules/
      Rules.swift
```

Importing a package never applies rules by convention. It only makes Swift
values available. The repository still opts in explicitly from
`BumperBowling.swift`:

```swift
import BumperBowlingCore
import BumperRules
```

## Built-In Primitives

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

Use `ContainSyntax(_:)` when the architecture rule only needs SwiftSyntax node
kind membership:

```swift
DoesNot(ContainSyntax(.forceUnwrapExpr), severity: .error)
```

Use `ContainSyntaxNode(_:)` when a repository needs a fact Bumper Bowling does
not name as a built-in rule. `SyntaxNodeMatcher` can match by SwiftSyntax node
kind, spelling, parent kind, ancestor kind, or any combination:

```swift
extension ComponentShape {
    static let noAvailabilityAnnotations = ComponentShape {
        DoesNot(
            ContainSyntaxNode(
                SyntaxNodeMatcher(
                    kind: .attribute,
                    spelling: .exact("available")
                )
            ),
            severity: .error
        )
    }
}
```

That keeps Bumper Bowling thin: consumers can enforce repo-specific syntax
facts without Bumper Bowling shipping a named rule or accepting an upstream PR.

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
