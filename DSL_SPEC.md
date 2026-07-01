# Bumper Bowling Swift DSL Specification

Bumper Bowling's configuration surface is Swift. The DSL is intentionally small and familiar to SwiftLint users: included/excluded paths, subsystems, opt-in rules, and configured rules with severities.

In 0.0, the DSL is the typed library API and sample authoring shape. The CLI still uses its built-in repository configuration; executing `BumperBowling.swift` as a config file is post-MVP.

The DSL compiles into architecture rules:

```text
BumperConfiguration -> ArchitectureConfiguration -> ArchitectureRules -> scanner/validator
```

## Design Goals

- Feel familiar beside SwiftLint.
- Keep the tool tiny.
- Parse strings into typed values at the boundary.
- Avoid generated accessors, dynamic lookup, JSON config, plugins, and clever DSL machinery.
- Keep language parsing inside adapters; SwiftSyntax belongs only to the Swift adapter.

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

    Subsystems {
        Subsystem(.core) {
            Paths("Sources/BumperBowlingCore")
            Modules("BumperBowlingCore")
        }

        Subsystem(.cli) {
            Paths("Sources/BumperBowling")
            Modules("BumperBowling")
            Dependencies(.core)
        }
    }

    Rules {
        ForbiddenImport(.error) {
            Modules("XCTest", "Testing")
        }

        SubsystemBoundary(.error)
        DuplicateOwnership(.error)
        DependencyCycle(.error)

        DomainModels(.warning) {
            Paths("Sources/BumperBowlingCore")
            Disallow(.any)
            Disallow(.broadExistential)
            Disallow(.storedVar)
            Disallow(.rawStringIdentity)
        }
    }

    OptInRules {
        EnumStateMachine(.error) {
            Paths("Sources/**/*Parser.swift")
        }
    }
}
```

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

## Language Adapters

Bumper Bowling is adapter-driven:

```text
Swift adapter -> SourceFileFacts -> RepositoryFacts -> RuleRegistry
```

Swift is the only language adapter in 0.0.

## MVP Testing Pattern

Bumper Bowling follows a tiny version of SwiftLint's self-test pattern:

- Every source-oriented rule has `RuleDescription` metadata.
- Rule examples use `↓` markers for expected violations.
- `verifyRule(...)` checks triggering and non-triggering examples.
- Command tests cover `scan` and `lint`.
- A self-lint test runs Bumper Bowling against this repository and records error-level findings.
