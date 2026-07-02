# Release Checklist

Use this before tagging a 0.1 release.

1. Confirm `LICENSE` is Apache 2.0.
2. Run `swift test`.
3. Run `swift test --filter BumperCommands`.
4. Run `swift test --filter SelfLint`.
5. Run `swift run bumper lint .`.
6. Confirm GitHub Actions is green on `main`.
7. Confirm `README.md`, `CHANGELOG.md`, and `docs/ARCHITECTURE_SNAPSHOT.md` are current.
8. Tag the release.
