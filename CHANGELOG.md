# Changelog

## 0.2.0 - 2026-07-07

- Added familiar Swift configuration through `BumperBowling.swift`.
- Loaded configurations the way SwiftPM loads `Package.swift`: compiled, cached, and run in a deny-default sandbox.
- Added the `bumper` CLI workflow for hooks and CI jobs, including `bumper config`.
- Made SwiftPM tags the canonical distribution path.
- Added consumer-owned rule vocabulary through `.bumper/Sources`.
- Added SwiftPM-native local rule packages through `.bumper/Package.swift` and the `BumperRules` product convention.
- Added `ComponentShape` and `AssertionShape` so repositories can define their own architecture vocabulary without Bumper Bowling shipping their tastes.
- Shipped a bundled Codex skill for agents composing Bumper Bowling rules.
- Made Bumper Bowling dogfood local shapes in `.bumper/Sources/BumperArchitecture.swift`.
- Tightened the public package surface to `BumperBowlingCore` and the `bumper` executable.
- Split DSL and SwiftSyntax support files by responsibility.
