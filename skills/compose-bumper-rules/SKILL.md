---
name: compose-bumper-rules
description: Use when creating, reviewing, or refactoring Bumper Bowling 0.5.2 architecture policy, standard Rules shapers, typed FactProvider rules, SyntaxQuery rules, per-file rules, or raw SyntaxVisitor escape hatches.
---

# Compose Bumper Rules

Author each invariant at the highest rung that can express it. Read the
repository's `docs/RULE_AUTHORING.md` when available; it is the canonical API
reference.

## Admission Gate

Before adding or retaining a rule:

1. State the invariant as `observed source fact + declared scope = mismatch`.
2. Apply the deletion test:
   - Do not recognize historical spellings or add compatibility aliases.
   - Do not check states rejected by the Swift compiler.
   - When a type or architecture change makes the bad state unconstructible,
     delete the rule and its rule-only support code instead of preserving it.
3. For a proposed rule below the standard-shaper rung, audit one existing rule
   at that rung or lower before adding another. Try to delete it, promote it to
   a higher rung, or share its existing fact/query. Record the audited rule and
   outcome in the change summary. If none exists, say so.
4. Explain concretely why the next higher rung cannot express the invariant.
5. Give every project rule an explicit, specific `summary`. Also document its
   rationale, scope, repair, proof, and deletion condition in the consumer's
   rule catalog. A generic factory default or a restatement of the rule ID is
   not documentation.

## Authoring Ladder

1. **Architecture DSL**: use typed `Architecture(AppComponent.self)`,
   `Component`, ownership, dependency, capability, and `Requires(...)`
   declarations. Use `ComponentShape` or `AssertionShape` only for reusable
   bundles of this policy.
2. **Standard shapers**: prefer an existing `Rules.*` factory such as
   `Rules.singleDeclaration`, `Rules.constructionOwnership`, or
   `Rules.canonicalTraversal`.
3. **Typed facts**: use `Rules.repository(...)` and request memoized providers
   with `context.facts(...)`. Reuse `BuiltInFacts` before defining a new
   `FactProvider`.
4. **Typed queries / per-file rules**: use `SyntaxQuery` roots and
   `Rules.files(...)` when typed facts are insufficient but parsed syntax is
   enough.
5. **Raw visitor**: use `Rules.visitor(...)` / `VisitorRule` with a real
   SwiftSyntax `SyntaxVisitor` only when typed queries cannot express the walk.
   This is a permanent escape hatch.

Do not skip a rung for convenience. Keep strings at configuration boundaries;
use typed symbols, paths, scopes, facts, and syntax nodes in rule logic.

## Workflow

1. Read `BumperBowling.swift`, `.bumper/Sources`, and `.bumper/Package.swift`.
2. Search existing rule IDs, shapes, shapers, providers, queries, and visitors.
3. Choose the narrowest honest `RuleScope` and the highest viable rung.
4. Put one-off vocabulary inline, repo-owned reusable code in
   `.bumper/Sources`, and genuinely cross-repo vocabulary in a local
   `.bumper/Package.swift` product named `BumperRules`.
5. Add project rules explicitly inside `Rules { ... }`; imports never apply
   rules automatically.
6. Update the consumer's rule catalog in the same change. If one visitor
   enforces several checks for parse efficiency, document each sub-invariant;
   one umbrella summary does not make hidden policy reviewable.

## Test Contract

Every project-defined `Rules.repository`, `Rules.files`, or visitor rule needs
both tests through `RuleTestHarness` and `VirtualRepository`:

- **Positive test**: a valid fixture produces no violations.
- **Mutation test**: minimally mutate that valid fixture into the forbidden
  state and assert the exact rule ID, path, message, available location, and
  evidence that the rule promises.

An analysis error must fail the run; never translate it into an empty match
set. Do not use Bumper Bowling for SwiftLint policy, compiler truth, symbol
resolution, macro expansion, or build-target truth.

The rule's metadata summary explains a violation at runtime. The catalog
explains why the project owns the rule and when it should be deleted. Both are
required; tests do not substitute for either.

## Validation

Run the smallest focused rule tests first, then validate the consumer surface:

1. `swift run bumper config .`
2. Focused `RuleTestHarness` positive and mutation tests
3. `swift run bumper lint . --timings`
4. `git diff --check`

Do not raise evaluation timeouts to hide a slow rule. Read the rule and fact
provider timings, reuse an existing fact, and remove repeated parsing or
quadratic accumulation before changing the execution budget.

## References

- Read `references/bumper-vocabulary.md` for exact 0.5.2 spellings.
- Read `references/shape-examples.md` for placement and test examples.
