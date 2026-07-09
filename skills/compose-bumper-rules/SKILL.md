---
name: compose-bumper-rules
description: Use when composing Bumper Bowling architecture rules, SyntaxNodeMatcher predicates, ComponentRequirement values, ComponentShape or AssertionShape bundles, BumperBowling.swift configs, .bumper/Sources rule vocabulary, or .bumper/Package.swift BumperRules packages for repo-owned architecture policy.
---

# Compose Bumper Rules

Use this skill when adding, reviewing, or refactoring Bumper Bowling rule vocabulary for a repo.

## Workflow

1. Inspect the repo first:
   - Read `BumperBowling.swift`.
   - Check for `.bumper/Sources`.
   - Check for `.bumper/Package.swift`.
   - Search existing `ComponentRequirement`, `ComponentShape`, and `AssertionShape` names before adding new ones.
2. Place vocabulary at the smallest useful scope:
   - Tiny one-off: define inline in `BumperBowling.swift`.
   - Repo-private reusable vocabulary: define Swift files in `.bumper/Sources`.
   - Shared local package vocabulary: use `.bumper/Package.swift` with a `BumperRules` library product.
3. Keep the concepts distinct:
   - Requirement: reusable bundle of source-fact checks, usually `ComponentRequirement`.
   - Shape: reusable bundle of architecture policy, usually `ComponentShape` or `AssertionShape`.
   - Rule: evaluated/scoped policy after `Requires`, `Applies`, or `ApplyAssertions`.
   - Scope: where a rule applies, such as component paths or exclusions. Do not call shapes scopes.
4. Compose from observable facts only. Bumper Bowling is syntax-first; do not claim type-checking, symbol resolution, semantic macro expansion, or compiler dependency truth.
   - Use `ContainSyntax(_:)` for raw SwiftSyntax kind membership.
   - Use `ContainSyntaxNode(SyntaxNodeMatcher(...))` for repo-specific syntax
     policy over kind, spelling, parent kind, or ancestor kind.
   - Use `CustomSyntaxRule` when the policy needs to walk raw SwiftSyntax
     trees or inspect node fields Bumper Bowling does not project.
5. Validate with the repo's checks, normally:
   - `swift test`
   - `swift run bumper lint .`
   - `git diff --check`

## Placement Rules

Prefer `.bumper/Sources` unless the user needs the vocabulary shared across repos as a Swift package.

If `.bumper/Package.swift` exists, Bumper Bowling treats `.bumper` as a SwiftPM package and expects a `BumperRules` library product. Do not also rely on copying `.bumper/Sources` into the runner in that repo.

Do not introduce JSON, registries, remote package policy, or auto-loaded shared rules. The repo must explicitly import and use the Swift values it wants.

## Authoring Guidance

- Use positive repo vocabulary where possible: `.domainCore`, `.uiBoundary`, `.globalAssertions`.
- Keep `BumperBowlingCore` primitives and mechanics separate from repo taste.
- Prefer `ComponentRequirement` for fact bundles.
- Prefer `ComponentShape` for component policy bundles.
- Prefer `AssertionShape` for repo-level assertions.
- Use `ContainSyntaxNode(SyntaxNodeMatcher(...))` for repo-specific SwiftSyntax
  facts that Bumper Bowling does not expose as named built-in requirements.
- Use `CustomSyntaxRule` for repo-specific rules over raw `SourceFileSyntax`.
  Import `SwiftSyntax` in the rule file when naming AST types.
- Do not invent Bumper-owned syntax taxonomies. Compose with SwiftSyntax
  `SyntaxKind` values and matcher structure.
- Use `ApplyAssertions(...)` inside `Assertions`.
- Keep findings explainable as observed fact plus declared expectation.

## References

- For exact vocabulary and examples, read `references/bumper-vocabulary.md`.
- For example layouts, read `references/shape-examples.md`.
