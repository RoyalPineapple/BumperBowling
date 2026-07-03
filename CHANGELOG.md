# Changelog

## 0.1.0 - Unreleased

- Added configuration in familiar Swift through `BumperBowling.swift`.
- Loaded configurations the way SwiftPM loads `Package.swift`: the file is
  compiled and run in a deny-default sandbox (no network, no writable paths,
  empty environment) that emits only the configuration value as JSON; scan and
  lint run in the host process. The build is cached against the file's content
  hash, so it happens once per change, not once per lint.
- Added `bumper config`, which loads the configuration and reports whether it
  is valid.
- Made `ArchitectureConfiguration` and its rule configurations `Codable`;
  SwiftSyntax node kinds are carried as typed `SyntaxKindName` values.
- Added `BumperBowlingTesting` as a test-suite interface over the core engine.
- Added the `bumper` CLI workflow for hooks and CI jobs.
- Added architecture snapshot tests, rule example tests, and self-lint product tests.
- Added `StringMatcher` and conservative direct string matching detection.
- Documented SwiftSyntax limits and future compiler-backed analysis requests.
