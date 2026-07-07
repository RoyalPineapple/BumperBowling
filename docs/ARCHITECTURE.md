# Bumper Bowling Architecture

Bumper Bowling is a Swift architectural linter: a Swift 6 assertion engine over SwiftSyntax-observed source facts.

The configuration language is specified in [DSL_SPEC.md](DSL_SPEC.md). Bumper Bowling ships one engine and one dumb interface over that engine: the `bumper` CLI for shell workflows, CI jobs, and product tests.

Bumper Bowling is designed to feel familiar beside SwiftLint: rules, severities, included/excluded paths, opt-in rules, reports, and a primary `bumper lint` command.

It runs alongside SwiftLint; it does not replace SwiftLint. SwiftLint owns local Swift style and code smells. Bumper Bowling owns the project's architectural rules: what each component owns, may depend on, may use, and must prove from SwiftSyntax facts.

SwiftLint configuration lives in `.swiftlint.yml`.

The tool should stay tiny. Prefer a small SwiftSyntax-first core, simple Swift configuration constructors, and boring CLI behavior over generated accessors, dynamic lookup, plugins, or clever configuration machinery.

The interesting part is the assertion model, not the wrapper. Bumper Bowling turns SwiftSyntax-visible source facts into a graph, then evaluates typed Swift declarations against that graph. The CLI target is intentionally a thin delivery surface for hooks, CI, and product tests.

## Core Model

```text
SwiftSyntax reads the code
Bumper Bowling records raw source facts
Those facts form an ArchitectureGraph
The configuration encodes typed assertions
Lint runs math over the graph
```

Bumper Bowling is not a semantic analyzer. If SwiftSyntax cannot observe something, Bumper Bowling cannot truthfully assert it. Compiler-backed checks belong in a later, separate `analyze` lane; candidate requests are tracked in [COMPILER_REQUESTS.md](COMPILER_REQUESTS.md).

The current SwiftSyntax fact surface is documented in [SWIFTSYNTAX_SURFACE.md](SWIFTSYNTAX_SURFACE.md).

## Configuration Loading

`BumperBowling.swift` loads the way SwiftPM loads `Package.swift`: it is a program, so it is compiled and run rather than parsed.

The configuration runner generates a small package that links `BumperBowlingCore`, compiles `BumperBowling.swift` into it, and runs the product in a deny-default sandbox — no network, no writable paths, an empty environment. The run computes the configuration value and prints it as JSON on stdout; nothing else crosses back, and scanning and linting run in the host process, never in configuration code.

The build is cached against the configuration's content hash (plus the toolchain identity and the runner's own hashes), so the compile happens once per change to `BumperBowling.swift`, not once per lint. An unchanged configuration loads from the cached binary with no build. `bumper config` loads the configuration and reports whether it is valid.

A configuration should declare the architecture the repository wants, then lower into assertions over observed facts. Prefer `Component`, `Owns`, `MayDependOn`, `MayUse`, and scoped fact assertions over free-floating negative rules.

`scan` and `snapshot` expose the observed graph Bumper Bowling can build from SwiftSyntax and repo shape. The graph holds every normalized Bumper Bowling fact, not every SwiftSyntax node: files, imports, declarations, properties, selected imperative constructs, subsystem nodes, and dependency edges. That graph is evidence for the declared bounds, not a source of generated policy.

SwiftSyntax remains the full source tree. `ArchitectureGraph` is the smaller projection rules operate on. Bumper Bowling should not duplicate SwiftSyntax node types or maintain a second syntax enum. Raw syntax checks use SwiftSyntax's `SyntaxKind`; richer local checks use computed extensions on real SwiftSyntax nodes through `node.bumper`.

Add graph facts only when they support an assertion Bumper Bowling can explain. Rules should be lean mathematical operations over facts: path matching, set membership, graph edges, and cycles. Keep scorecards explainable: report the observed graph fact, the declared lane, and why they do not match.

Semantic shorthand names are not special engine concepts. `ComponentRequirement` composes `SourceFactRule` values, then `Requires(...)` applies scope and severity. Built-in shorthand and user-defined shorthand lower into the same raw graph assertions.

Consumer repositories can place Swift files under `.bumper/Sources` to define
their own `ComponentRequirement`, `ComponentShape`, and `AssertionShape`
vocabulary. Those files compile into the temporary configuration runner beside
`BumperBowling.swift`. They do not add a plugin boundary or hidden evaluator;
they are just consumer-owned Swift values that lower into the same
`ArchitectureConfiguration` data as inline configuration code.

Reusable vocabulary can also live in a conventional `.bumper/Package.swift`
SwiftPM package. The generated runner depends on its `BumperRules` library
product so `BumperBowling.swift` can import it; this does not discover,
download, or apply rules.

## Product Lane

Bumper Bowling lives between linting and compilation.

- SwiftLint owns local style, convention, and code smells.
- The compiler owns type checking, symbol resolution, macro expansion, and build truth.
- Bumper Bowling owns architectural rules when they can be checked from SwiftSyntax facts and repo metadata.

That lane is especially useful for agentic work because it gives an automated editor a formal contract before it touches the repository, then leaves a scorecard after it does.

## Lanes

A lane is a declared architectural boundary.

Most lanes are `Component` values. A component lane has:

- owned paths
- module aliases
- allowed dependencies
- allowed capabilities
- scoped assertions

Some assertions use narrower lanes. `RequiresScoped(...)` and assertion path filters apply a rule to a specific path scope inside the repository.

The rule engine should always know which lane a finding came from. A report without a lane is hard to fix.

## Subsystems

- `BumperBowlingCore` owns parsing, rule construction, repository scanning, architecture modeling, and linting.
- `BumperBowling` is the CLI adapter for hooks and CI jobs. It may depend on `BumperBowlingCore`; core must not depend on the CLI.
- Tests may import product modules and testing frameworks, but production targets must not import test frameworks.
- Language parsing is SwiftSyntax-driven. Swift is the only language surface in 0.1.

## Architectural Rules

- Core domain rules must be represented as typed values before use.
- Swift configuration structs are boundary/input shapes only; scanning and validation operate on typed rules.
- Strings are parsed into domain types at boundaries. Core models should carry `SubsystemID`, `ModuleName`, paths, declaration names, and attributes as types.
- Empty subsystem names, module names, path prefixes, and unknown dependency references are invalid.
- Duplicate subsystem IDs, module aliases, and path ownership are invalid.
- SwiftSyntax parsing is syntax-only. Reports must not imply compiler-level symbol resolution.
- Public API detection is syntactic and covers declarations marked `public` or `open`.
- Stateful parsers use explicit enum-based state machines. Stateless fact collection should stay as direct functional projection over SwiftSyntax nodes.
- Avoid `Any` and broad existential abstractions in domain code.
- Avoid code generation unless it directly supports a core linting workflow.

## Swift Rules

- Use Swift 6 strict concurrency.
- Public model types that cross subsystem boundaries should be `Sendable`.
- Prefer immutable value types for parsed architecture state.
- Prefer `let` for domain data. Use local mutation only as a scoped builder detail when Swift APIs require callback-style accumulation.
- Do not add `@unchecked Sendable` without a local explanation.
- Do not use `swift build` for future iOS projects in this repo family; use `xcodebuild` when iOS SDK access matters.
