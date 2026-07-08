# Agent Lanes

- Bumper Bowling keeps agents in their lane by validating changes against the declared codebase shape.
- Treat every violation as a scorecard entry: observed graph fact, declared lane, mismatch.
- Fix the code first; update the lane only when the intended architecture actually changed.
- Keep changes scoped to the component named by the task.
- Update `BumperBowling.swift` only when the architectural contract intentionally changes.
- Update `docs/ARCHITECTURE_SNAPSHOT.md` when command flow, core pipeline types, or rule IDs change.
- Run `swift test` before reporting implementation work complete.
- Run `swift run bumper lint .` before shipping changes that affect config loading, scanning, or linting.
- Run `swiftlint lint` when SwiftLint is available.
- Make sure Bumper Bowling's self-lint product test still passes after architectural model or rule changes.
- Do not make `BumperBowlingCore` depend on the CLI target.
- Keep `BumperBowling` dumb. It is a shipped interface over the core engine, not a separate engine.
- Preserve strict concurrency settings.
- Keep parsing SwiftSyntax-first. Use SwiftSyntax/SwiftParser for Swift parsing rather than regular expressions.
- Parse strings into domain types at boundaries; do not pass raw strings through core architecture logic.
- Use explicit enum state machines when parser progress has state; keep stateless source-fact collection as direct projection over syntax.
- Do not introduce stored properties explicitly typed as `Any` or broad existentials in guarded scopes.
- Keep the tool tiny; avoid generated accessors, dynamic lookup, and nonessential framework code.
