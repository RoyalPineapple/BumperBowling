# Agent Guardrails

- Keep changes scoped to the subsystem named by the task.
- Update `BumperBowling.swift` only when the architectural contract intentionally changes.
- Regenerate `SYSTEM_DIAGRAM.md` with `swift run -q bumper diagram . > SYSTEM_DIAGRAM.md` when command flow, core pipeline types, or rule IDs change.
- Run `swift test` before reporting implementation work complete.
- Run `swiftlint lint` when SwiftLint is available.
- Run `swift run bumper lint .` after architectural model or rule changes.
- Do not make `BumperBowlingCore` depend on the CLI target.
- Preserve strict concurrency settings.
- Keep language-specific parsing inside language adapters. Use SwiftSyntax/SwiftParser for Swift parsing rather than regular expressions.
- Parse strings into domain types at boundaries; do not pass raw strings through core architecture logic.
- Model parser progress with explicit enum state machines whose cases carry the parsed data.
- Do not introduce `Any` or broad existential abstractions in the domain model.
- Keep the tool tiny; avoid generated accessors, dynamic lookup, and nonessential framework code.
