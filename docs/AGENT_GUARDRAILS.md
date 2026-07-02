# Agent Guardrails

- Bumper Bowling keeps agents in their lane by validating changes against the declared codebase shape.
- Treat every violation as a receipt: observed graph fact, declared lane, mismatch.
- Fix the code first; update the lane only when the intended architecture actually changed.
- Keep changes scoped to the subsystem named by the task.
- Update `BumperBowling.swift` only when the architectural contract intentionally changes.
- Regenerate `docs/ARCHITECTURE_SNAPSHOT.md` with `swift run -q bumper snapshot . > docs/ARCHITECTURE_SNAPSHOT.md` when command flow, core pipeline types, or rule IDs change.
- Run `swift test` before reporting implementation work complete.
- Run `swiftlint lint` when SwiftLint is available.
- Run `swift run bumper lint .` after architectural model or rule changes.
- Do not make `BumperBowlingCore` depend on the CLI target.
- Preserve strict concurrency settings.
- Keep parsing SwiftSyntax-first. Use SwiftSyntax/SwiftParser for Swift parsing rather than regular expressions.
- Parse strings into domain types at boundaries; do not pass raw strings through core architecture logic.
- Model parser progress with explicit enum state machines whose cases carry the parsed data.
- Do not introduce stored properties explicitly typed as `Any` or broad existentials in guarded scopes.
- Keep the tool tiny; avoid generated accessors, dynamic lookup, and nonessential framework code.
