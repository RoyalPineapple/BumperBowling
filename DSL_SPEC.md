# Bumper Bowling Swift DSL Specification

Bumper Bowling's configuration surface is Swift. The DSL is intentionally small and familiar to SwiftLint users: included/excluded paths, subsystems, opt-in rules, and configured rules with severities.

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
            AppliesTo(.production)
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

## Language Adapters

Bumper Bowling is adapter-driven:

```text
Swift adapter -> SourceFileFacts -> RepositoryFacts -> RuleRegistry
```

Swift is the only implemented adapter in the MVP. Objective-C, C, C++, and Metal are future adapters.

## MVP Testing Pattern

Bumper Bowling follows a tiny version of SwiftLint's self-test pattern:

- Every source-oriented rule has `RuleDescription` metadata.
- Rule examples use `↓` markers for expected violations.
- `verifyRule(...)` checks triggering and non-triggering examples.
- Command tests cover `scan` and `lint`.
- A self-lint test runs Bumper Bowling against this repository and records error-level findings.
