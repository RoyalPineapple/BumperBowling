# Changelog

## 0.1.0 - Unreleased

- Added runnable Swift DSL configuration through `BumperBowling.swift`.
- Added static interpretation of configurations written in familiar Swift
  syntax: they load through SwiftSyntax without compiling or executing any
  configuration code.
- Added `bumper config`, which reports a configuration's loading lane
  (statically interpreted or sandbox-executed), the reason, and validity.
- Hardened executable configurations: the runner now only evaluates the
  configuration value (scan and lint run in the host process) inside a
  deny-default sandbox with an empty environment, no network, and no writable
  paths.
- Made `ArchitectureConfiguration` and its rule configurations `Codable`;
  SwiftSyntax node kinds are carried as typed `SyntaxKindName` values.
- Added `BumperBowlingTesting` as a test-suite interface over the core engine.
- Added the `bumper` CLI workflow for hooks and CI jobs.
- Added architecture snapshot tests, rule example tests, and self-lint product tests.
- Added `StringMatcher` and conservative direct string matching detection.
- Documented SwiftSyntax limits and future compiler-backed analysis requests.
