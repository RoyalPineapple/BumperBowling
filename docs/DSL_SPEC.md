# Bumper Bowling Swift DSL Specification

Bumper Bowling's assertion surface is Swift. The DSL is intentionally small and familiar to SwiftLint users, but its center is positive architecture: layers own code, depend on other layers, declare what they do not use, and require modeling guarantees.

In 0.0, the DSL is the typed library API and sample authoring shape. The CLI still uses its built-in repository configuration; executing `BumperBowling.swift` as a config file is post-MVP.

The DSL declares the architecture the repository wants. SwiftSyntax supplies what is visible in source. Bumper Bowling checks whether the observed syntax facts satisfy the declared architecture.

`bumper scan` discovers the architecture graph the code currently expresses. The DSL declares which parts of that graph are intended bounds.

Candidate assertions may be discovered from the graph, but they are not enforced until written into the DSL.

The graph is intentionally not a second AST. It is a compact projection of facts Bumper rules can use.

The DSL compiles into typed architecture rules:

```text
BumperConfiguration -> ArchitectureConfiguration -> ArchitectureRules -> scanner -> ArchitectureGraph -> validator
```

## Design Goals

- Feel familiar beside SwiftLint without overlapping SwiftLint's style lane.
- Keep the tool tiny.
- Prefer positive architecture vocabulary over free-floating negative rules.
- Parse strings into typed values at the boundary.
- Avoid generated accessors, dynamic lookup, JSON config, plugins, and clever DSL machinery.
- Keep parsing SwiftSyntax-first and Swift-only in 0.0.

## Default File Shape

```swift
import BumperBowlingCore

let configuration = BumperConfiguration {
    Defaults(.strict)

    Included {
        "Sources"
    }

    Excluded {
        ".build"
        "DerivedData"
    }

    Architecture {
        Layer(.core) {
            Owns("Sources/BumperBowlingCore")
            Modules("BumperBowlingCore")
            DoesNotUse("XCTest", "Testing", severity: .error)
            Requires(.explicitDomainSurfaces, .typedIdentity, .immutableState, severity: .warning)
            Requires(.enumStateMachine, severity: .error, in: "Sources/BumperBowlingCore/SwiftFileParser.swift")
        }

        Layer(.cli) {
            Owns("Sources/BumperBowling")
            Modules("BumperBowling")
            DependsOn(.core)
            DoesNotUse("XCTest", "Testing", severity: .error)
        }
    }

    Rules {
        SubsystemBoundary(.error)
        DuplicateOwnership(.error)
        DependencyCycle(.error)
    }
}
```

## Core Vocabulary

- `Layer`: a named architectural area.
- `Owns`: paths owned by that layer.
- `Modules`: module aliases that identify that layer in imports.
- `DependsOn`: an intended dependency edge.
- `MayDependOn`: an allowed optional dependency edge.
- `DoesNotUse`: layer-scoped modules or frameworks that must not appear in imports.
- `Requires`: positive modeling guarantees that derive syntax-first checks.

Current modeling requirements include:

- `.explicitDomainSurfaces`: disallow `Any` and broad existentials where configured.
- `.typedIdentity`: disallow raw `String` stored identity where configured.
- `.immutableState`: disallow mutable stored properties where configured.
- `.functionalCore`: disallow observed imperative constructs where configured, such as loops, assignments, mutable bindings, `inout` expressions, and `mutating` declarations.
- `.enumStateMachine`: require parser/workflow files to declare an enum state machine where configured.

## MVP Commands

```bash
bumper init [root]
bumper lint [root]
bumper scan [root]
bumper explain <path>
```

## MVP Rules

- `forbidden_import`
- `subsystem_boundary`
- `duplicate_ownership`
- `dependency_cycle`
- `domain_models`
- `enum_state_machine`

Severities are:

```swift
off
note
warning
error
```

Only `error` fails `bumper lint`.

`domain_models` is syntax-first in 0.0. It checks explicit stored-property type annotations exactly enough to catch mutable stored properties, `Any`, `any ...`, and raw `String` in configured paths. It does not claim compiler-level type inference or full signature analysis.

See [MODELING_ASSERTIONS.md](MODELING_ASSERTIONS.md) for an example of using Bumper Bowling for architecture and domain modeling assertions without overlapping SwiftLint style rules.

## SwiftSyntax Boundary

Bumper Bowling is SwiftSyntax-driven:

```text
SwiftSyntax -> SourceFileFacts -> RepositoryFacts -> RuleRegistry
```

Swift is the only language surface in 0.0. The DSL must not promise facts SwiftSyntax cannot observe, such as symbol resolution, inferred types, or compiler-level dependency truth.

## MVP Testing Pattern

Bumper Bowling follows a tiny version of SwiftLint's self-test pattern:

- Every source-oriented rule has `RuleDescription` metadata.
- Rule examples use `↓` markers for expected violations.
- `verifyRule(...)` checks triggering and non-triggering examples.
- Command tests cover `scan` and `lint`.
- A self-lint test runs Bumper Bowling against this repository and records error-level findings.
