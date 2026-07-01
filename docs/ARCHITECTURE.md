# Bumper Bowling Architecture

Bumper Bowling is a Swift 6 command line tool and core library for asserting architecture over SwiftSyntax-observed source facts.

The Swift DSL is specified in [DSL_SPEC.md](DSL_SPEC.md). The DSL is the typed assertion API for now. In 0.0, CLI commands use the built-in repository configuration; loading `BumperBowling.swift` from disk is intentionally post-MVP.

Bumper Bowling is designed to feel familiar beside SwiftLint: rules, severities, included/excluded paths, opt-in rules, baselines, reporters, and a primary `bumper lint` command.

It runs alongside SwiftLint; it does not replace SwiftLint. SwiftLint owns local Swift style and code smells. Bumper Bowling owns architectural boundaries and repository-specific taste that can be seen in Swift syntax and configured repo shape.

SwiftLint configuration lives in `.swiftlint.yml`.

The tool should stay tiny. Prefer a small SwiftSyntax-first core, simple Swift DSL constructors, and boring CLI behavior over generated accessors, dynamic lookup, plugins, or clever configuration machinery.

## Core Model

```text
SwiftSyntax observes source syntax
Bumper DSL declares architectural expectations
Bumper builds deterministic facts
Rules assert over those facts
```

Bumper Bowling is not a semantic analyzer. If SwiftSyntax cannot observe something, Bumper Bowling cannot truthfully assert it. Compiler-backed checks belong in a later, separate `analyze` lane.

## Subsystems

- `BumperBowlingCore` owns parsing, rule construction, repository scanning, architecture modeling, and linting.
- `BumperBowling` is the CLI adapter. It may depend on `BumperBowlingCore`; core must not depend on the CLI.
- Tests may import product modules and testing frameworks, but production targets must not import test frameworks.
- Language parsing is SwiftSyntax-driven. Swift is the only language surface in 0.0.

## Architectural Rules

- Core domain rules must be represented as typed values before use.
- Swift configuration structs are boundary/input shapes only; scanning and validation operate on typed rules.
- Strings are parsed into domain types at boundaries. Core models should carry `SubsystemID`, `ModuleName`, paths, declaration names, and attributes as types.
- Empty subsystem names, module names, path prefixes, and unknown dependency references are invalid.
- Duplicate subsystem IDs, module aliases, and path ownership are invalid.
- SwiftSyntax parsing is syntax-only. Reports must not imply compiler-level symbol resolution.
- Public API detection is syntactic and covers declarations marked `public` or `open`.
- Parsers use explicit enum-based state machines. State cases carry their data; parsing transitions produce the next state.
- Avoid `Any` and broad existential abstractions in domain code.
- Avoid code generation unless it directly supports a core linting workflow.

## Swift Rules

- Use Swift 6 strict concurrency.
- Public model types that cross subsystem boundaries should be `Sendable`.
- Prefer immutable value types for parsed architecture state.
- Prefer `let` for domain data. Use local mutation only as a scoped builder detail when Swift APIs require callback-style accumulation.
- Do not add `@unchecked Sendable` without a local explanation.
- Do not use `swift build` for future iOS projects in this repo family; use `xcodebuild` when iOS SDK access matters.
