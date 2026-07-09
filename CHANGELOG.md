# Changelog

## Unreleased

### Breaking

- Renamed the public architecture model from subsystem terminology to component
  terminology so it matches the DSL and documentation. This changes public
  source names and Codable field names such as `subsystems`,
  `SubsystemConfiguration`, `SubsystemID`, and `subsystemBoundary` to their
  component equivalents.
- Added generic syntax-node predicates over SwiftSyntax `SyntaxKind`, spelling,
  parent kind, and ancestor kind so repositories can enforce their own syntax
  policy without Bumper Bowling shipping repo-specific rule taxonomy.

### Added

- Added JSON output for `bumper lint` and `bumper scan` with `--format json`.
- Added `bumper lint --fail-on none|note|warning|error` for advisory CI rollout.
- Added `bumper baseline create` and `bumper lint --baseline` for incremental
  adoption in repos with existing architecture violations.
- Added `bumper lint --progress` and `bumper scan --progress` for large-repo
  visibility.
- Added `BUMPER_CACHE_DIR` so CI can control where compiled configuration
  runners are cached.

### Fixed

- Fixed generated configuration-runner manifests to use an explicit
  `BumperBowling` package identity, so path-based checkouts work even when the
  checkout directory has a different name.
- Fixed composed rule settings so shapes preserve each scoped path, exclusion,
  and severity instead of collapsing compatible rule families into one merged
  setting before linting.

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
