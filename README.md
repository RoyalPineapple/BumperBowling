# Bumper Bowling

[![CI](https://github.com/RoyalPineapple/BumperBowling/actions/workflows/ci.yml/badge.svg)](https://github.com/RoyalPineapple/BumperBowling/actions/workflows/ci.yml)

Bumper Bowling is a tiny Swift 6 architectural linter for Swift repositories. It is meant to run beside SwiftLint: SwiftLint owns local style, while Bumper Bowling owns architecture boundaries and repository-specific taste.

## Status

This is 0.0 shaping work. The Swift DSL is available as the typed configuration API, and the CLI currently uses the built-in Bumper Bowling repository configuration.

## Commands

```bash
swift run bumper lint .
swift run bumper scan .
swift run bumper explain Sources/BumperBowlingCore/ArchitectureLinter.swift
```

## License

Apache License 2.0. See [LICENSE](LICENSE).
