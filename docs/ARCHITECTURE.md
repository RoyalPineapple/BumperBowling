# Bumper Bowling Architecture

Bumper Bowling is a Swift 6 command line tool and core library for asserting architecture over SwiftSyntax-observed source facts.

The Swift DSL is specified in [DSL_SPEC.md](DSL_SPEC.md). The DSL is the typed assertion API for now. In 0.0, CLI commands use the built-in repository configuration; loading `BumperBowling.swift` from disk is intentionally post-MVP.

Bumper Bowling is designed to feel familiar beside SwiftLint: rules, severities, included/excluded paths, opt-in rules, baselines, reporters, and a primary `bumper lint` command.

It runs alongside SwiftLint; it does not replace SwiftLint. SwiftLint owns local Swift style and code smells. Bumper Bowling owns the formal codebase shape: what each component owns, may depend on, may use, and must prove from SwiftSyntax facts.

SwiftLint configuration lives in `.swiftlint.yml`.

The tool should stay tiny. Prefer a small SwiftSyntax-first core, simple Swift DSL constructors, and boring CLI behavior over generated accessors, dynamic lookup, plugins, or clever configuration machinery.

## Core Model

```text
SwiftSyntax reads the code
Bumper records raw source facts
Those facts form an ArchitectureGraph
The Swift DSL encodes typed assertions
Lint runs math over the graph
```

Bumper Bowling is not a semantic analyzer. If SwiftSyntax cannot observe something, Bumper Bowling cannot truthfully assert it. Compiler-backed checks belong in a later, separate `analyze` lane.

The current SwiftSyntax fact surface is documented in [SWIFTSYNTAX_SURFACE.md](SWIFTSYNTAX_SURFACE.md).

The DSL should declare the architecture the repository wants, then lower into assertions over observed facts. Prefer `Component`, `Owns`, `MayDependOn`, `MayUse`, and scoped fact assertions over free-floating negative rules.

`scan` and `snapshot` expose the observed graph Bumper Bowling can build from SwiftSyntax and repo shape. The graph holds every normalized Bumper fact, not every SwiftSyntax node: files, imports, declarations, properties, selected imperative constructs, subsystem nodes, and dependency edges. That graph is evidence for the declared bounds, not a source of generated policy.

SwiftSyntax remains the full source tree. `ArchitectureGraph` is the smaller projection rules operate on. Add graph facts only when they support an assertion Bumper Bowling can explain. Rules should be lean mathematical operations over facts: path matching, set membership, graph edges, and cycles. Keep receipts for every finding: report the observed graph fact, the declared lane, and why they do not match.

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
