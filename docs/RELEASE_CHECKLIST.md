# Release Checklist

Use this before tagging a SwiftPM release. SwiftPM tags are the canonical
distribution artifact for Bumper Bowling.

1. Confirm `LICENSE` is Apache 2.0.
2. Confirm `Package.swift` exposes only the intended public products.
3. Run `swift package dump-package`.
4. Run `BUMPER_RUNNER_BUILD_CONFIGURATION=debug swift test`; policy tests cover the production `release` default.
5. Run `swift run bumper lint .`.
6. Confirm GitHub Actions is green on `main`.
7. Confirm `README.md`, `CHANGELOG.md`, and `docs/ARCHITECTURE_SNAPSHOT.md` are current.
8. Tag the release, for example `git tag 0.2.0`.
9. Push the tag: `git push origin 0.2.0`.
