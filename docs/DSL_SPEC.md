# Bumper Bowling Configuration Language Specification

Bumper Bowling's assertion surface is Swift. The configuration language is intentionally small and familiar to SwiftLint users, but its center is architecture snapshot testing: components own code, declare dependency edges and import capabilities, and require specific SwiftSyntax-observed facts.

Bumper Bowling exposes the configuration language through the `bumper` CLI. The CLI loads `BumperBowling.swift` for shell workflows, CI jobs, and product tests.

A configuration declares the shape the repository wants using Swift types. SwiftSyntax supplies what is visible in source. Bumper Bowling checks whether the observed graph facts satisfy the declared shape.

`bumper scan` shows the architecture graph the code currently expresses. The configuration declares the bounds; scan is evidence for those bounds.

The graph is intentionally not a second AST. It is a compact projection of facts Bumper Bowling rules can use, and it is the evidence trail for every finding.

The configuration compiles into typed architecture rules. Validation is deliberately lean math over the parsed graph: path scope, set membership, edge checks, and cycle detection.

Facts become rules when the configuration scopes them. The atom is
`SourceFactRule`; a `ComponentRequirement` is a composable set of those atoms.
Bumper Bowling includes small built-in requirement primitives and conveniences,
and repositories can define their own vocabulary:

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

`Requires(.valueCore, severity: .error)` still lowers into raw graph checks over stored-property facts, syntax-construct facts, and enum facts.

Consumer-owned shape files can live under `.bumper/Sources`. Bumper Bowling
compiles those Swift files into the temporary configuration runner beside
`BumperBowling.swift`, then runs the resulting executable in the same sandboxed
evaluation path. This lets a repository define its own house vocabulary without
adding those names to Bumper Bowling itself:

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

extension AssertionShape {
    static let global = AssertionShape {
        DependencyBoundaries(.error)
        SingleOwner(.error)
        AcyclicDeclaredDependencies(.error)
    }
}
```

```swift
// BumperBowling.swift
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

Those shapes are still just typed Swift values. `ComponentShape` bundles
component elements such as capabilities, dependencies, and requirements.
`AssertionShape` bundles repo-level `RuleConfiguration` values. Loading a shape
does not add hidden facts; it only gives the consumer a reusable spelling for
the facts and policies Bumper Bowling can already evaluate.

For shared local Swift packages, put a normal SwiftPM package at
`.bumper/Package.swift`. Bumper Bowling automatically adds that package to the
generated configuration runner and expects a `BumperRules` library product:

```text
.bumper/
  Package.swift
  Sources/BumperRules/Rules.swift
```

The package does not define or apply rules by convention alone. It only makes
Swift values importable; `BumperBowling.swift` still chooses what to use:

```swift
import BumperRules
```

Custom rules are the escape hatch for repository-specific checks that cannot be
named ahead of time by Bumper Bowling. They are still typed and opt-in:

```swift
let configuration = BumperConfiguration {
    Architecture {
        Component(.score) {
            Owns("Sources/TheScore")
            Modules("TheScore")
        }
    }

    CustomRules()
}
```

```swift
// .bumper/Sources/CustomRules.swift
import BumperBowlingCore

let customRules = CustomRuleSet {
    CustomRule("the_score.import_allow_list", severity: .error) { context in
        let allowedImports = Set(["Foundation"])

        return context.files(inComponent: "score").flatMap { file in
            file.imports
                .filter { !allowedImports.contains($0) }
                .map { module in
                    CustomRuleFailure(
                        path: file.path,
                        message: "\(file.component) imports non-allowlisted module \(module)",
                        evidence: ViolationEvidence(
                            observed: module,
                            expectation: "allowed imports: Foundation"
                        )
                    )
                }
        }
    }
}
```

Bumper Bowling owns the scan. The custom worker receives `CustomRuleInput` as
Codable data and returns `CustomRuleOutput` as Codable findings; the closures do
not cross the process boundary.

Raw syntax assertions use SwiftSyntax's own `SyntaxKind` values:

```swift
Requires(RequireSyntax(.enumDecl), severity: .error)
Requires(DisallowSyntax(.forceUnwrapExpr), severity: .warning)
```

Bumper Bowling does not maintain a parallel enum of SwiftSyntax nodes. Facts that need typed access to syntax fields are computed from real SwiftSyntax node types through `node.bumper` views.

```text
BumperConfiguration -> ArchitectureConfiguration -> ArchitectureRules -> scanner -> ArchitectureGraph -> validator
```

## Design Goals

- Feel familiar beside SwiftLint without overlapping SwiftLint's style lane.
- Keep the tool tiny.
- Prefer positive architecture vocabulary over free-floating negative rules.
- Make every violation explainable as observed fact plus declared lane.
- Support agentic coding loops by making architecture executable in hooks, CI, and tests.
- Parse strings into typed values at the boundary.
- Avoid generated accessors, dynamic lookup, JSON config, plugins, and clever configuration machinery.
- Keep parsing SwiftSyntax-first and Swift-only.
- Do not duplicate SwiftSyntax's syntax model. Extend and compose over SwiftSyntax types instead.

## Default File Shape

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
    }
}
```

## Core Vocabulary

- `Component`: a named architectural area.
- `Owns`: paths owned by that component.
- `Modules`: module aliases that identify that component in imports.
- `MayDependOn`: an allowed optional dependency edge.
- `DoesNotDependOn`: a forbidden dependency edge.
- `MayUse`: allowed capability imports for a component.
- `DoesNotUse`: component-scoped modules or frameworks that must not appear in imports.
- `Declare`: a public declaration predicate over parsed declaration facts.
- `Declares`: sugar for `Does(Declare(...))`.
- `ContainSyntax`: a SwiftSyntax node-kind predicate over parsed syntax nodes.
- `ContainSyntaxNode`: a generic predicate over observed SwiftSyntax node
  family, node kind, and spelling.
- `Does`: asserts that a predicate is present in the component graph.
- `DoesNot`: asserts that a predicate is absent from the component graph.
- `StringMatcher`: typed matching for name-like facts; string literals are exact matches, with `.contains`, `.prefix`, and `.suffix` available explicitly.
- `Requires`: positive modeling guarantees that derive syntax-first checks.
- `ComponentShape`: reusable component policy bundle owned by the consumer.
- `AssertionShape`: reusable repo-level assertion bundle owned by the consumer.
- `ApplyAssertions`: applies an `AssertionShape` inside `Assertions`.
- `Disallows`: concrete syntax nodes that must not appear in a component.
- `NoDirectStringMatching`: a syntax-first assertion that keeps direct string matching inside the matcher implementation.
- `Assertions`: graph-level assertions such as ownership and dependency shape.

Current modeling requirements include:

- `.explicitDomainSurfaces`: shorthand for no `Any` or broad existential stored properties.
- `.typedIdentity`: shorthand for no raw `String` stored properties.
- `.computedState`: shorthand for no stored properties in the configured scope.
- `.functionalCore`: shorthand for no selected imperative syntax constructs.
- `.noStoredProperties`: disallow any stored property.
- `.noAnyStoredProperties`: disallow stored properties explicitly typed as `Any`.
- `.noBroadExistentialStoredProperties`: disallow stored properties with explicit `any ...` types.
- `.noBoolStoredProperties`: disallow stored properties explicitly typed as `Bool`.
- `.noOptionalStoredProperties`: disallow stored properties explicitly typed as optional.
- `.noRawStringStoredProperties`: disallow stored properties explicitly typed as `String`.
- `.immutableStoredState`: disallow mutable stored properties where configured.
- `.enumStateMachine`: require parser/workflow files to declare an enum state machine where configured.

Concrete imperative facts can be disallowed directly:

```swift
Disallows(.assignment, .loop, .mutableBinding)
```

## Commands

```bash
bumper init [root]
bumper lint [root]
bumper scan [root]
bumper snapshot [root]
bumper config [root]
bumper explain <path>
```

## Rules

- `forbidden_import`
- `component_boundary`
- `duplicate_ownership`
- `declared_dependency_cycle`
- `stored_properties`
- `syntax_constructs`
- `enum_state_machine`
- `syntax_kinds`
- `public_declarations`

Direct string matching is conservative. SwiftSyntax can show an operator token or a member-call spelling, but it does not type-check the operands. Bumper Bowling flags obvious string-like comparisons and string matching calls; a compiler-backed analyzer would be needed for perfect `String` certainty.

Severities are:

```swift
off
note
warning
error
```

Only `error` fails `bumper lint`.

`stored_properties` is syntax-first. It checks explicit stored-property type annotations exactly enough to catch mutable stored properties, `Any`, `any ...`, and raw `String` in configured paths. It does not claim compiler-level type inference or full signature analysis.

See [RULE_AUTHORING.md](RULE_AUTHORING.md) for guidance on composing
repository-owned requirements, component shapes, assertion shapes, and examples.

## SwiftSyntax Boundary

Bumper Bowling is SwiftSyntax-driven:

```text
SwiftSyntax -> SourceFileFacts -> RepositoryFacts -> ArchitectureGraph -> RuleRegistry
```

Swift is the only language surface. The configuration language must not promise facts SwiftSyntax cannot observe, such as symbol resolution, inferred types, or compiler-level dependency truth.

See [SWIFTSYNTAX_SURFACE.md](SWIFTSYNTAX_SURFACE.md) for the current fact surface.

## Testing Pattern

Bumper Bowling follows a tiny version of SwiftLint's self-test pattern:

- Every source-oriented rule has `RuleDescription` metadata.
- Rule examples use `↓` markers for expected violations.
- `verifyRule(...)` checks triggering and non-triggering examples.
- Command tests cover `scan` and `lint`.
- A self-lint test runs Bumper Bowling against this repository and records error-level findings.
