# Migrating to 0.5.0

0.5.0 replaces the closed configuration surface and the separate custom-rule
worker with one open rule engine and one project entry point. There are no
compatibility aliases; every removed symbol has an exact replacement.

## Configuration

| Removed | Replacement |
| --- | --- |
| `BumperConfiguration { ... }` | `BumperProject { ... }` |
| `let configuration = ...` in `BumperBowling.swift` | `let bumper = BumperProject { ... }` |
| `configuration.architectureConfiguration` | `bumper.architecture` |
| `Assertions { ... }` | `Rules { ... }` |
| `CustomRules()` / `CustomRules(maxConcurrentRuleJobs:)` | Nothing — add project rules to `Rules { ... }`; there is no opt-in marker or worker concurrency knob. |
| `CustomRuleWorkerConfiguration` | Removed with no replacement (no second worker exists). |

`Architecture { ... }` is unchanged, and the new typed
`Architecture(MyComponentKey.self) { ... }` accepts your own `ComponentKey`
enum so `Component(.core)` / `MayDependOn(.core)` are compiler-checked.

## Custom rules

| Removed | Replacement |
| --- | --- |
| `CustomRuleSet { ... }` | `RuleSet { ... }` |
| `CustomRule("id", severity:) { context in ... }` | `Rules.repository("id", severity:) { context in ... }` |
| `CustomSyntaxRule("id", severity:) { file in ... }` | `Rules.files("id", severity:) { file in ... }` |
| `CustomRuleFailure` | `RuleFailure` |
| `CustomRuleInput` | `RepositoryInput` (host-to-runner wire type; rule code receives `RuleContext`) |
| `CustomRuleOutput` / `CustomRuleFinding` | `RuleReport` / `RuleViolation` |
| `CustomRuleFileFacts` | `SourceFileContext(descriptor:source:)` |
| `CustomRuleContext` | `RuleContext` |
| `context.files(inComponent:)` + `file.imports` | `context.facts(BuiltInFacts.imports).occurrences` (or any other `FactProvider`) |
| A top-level `let customRules` value | A `RuleSet` value referenced inside `Rules { ... }` |

## Reports and evaluation

| Removed | Replacement |
| --- | --- |
| `ArchitectureLinter` | `RuleSet.evaluate(configuration:repository:)` via `BumperProject.evaluate(_:)` |
| `LintReport` | `RuleReport` |
| `ArchitectureViolation` | `RuleViolation` (`ruleID` and `severity` are conveniences over `rule` metadata) |
| `RuleRegistry` | Nothing — rules are values in a `RuleSet`; there is no registry. |
| `RuleDescription` | `RuleMetadata` |
| `RuleSet.evaluateConcurrently(...)` | `RuleSet.evaluate(...)` — evaluation is sequential in V1. |

## Runner

The two cached executables (configuration runner and custom-rule worker) are
one cached `BumperProjectRunner` with two modes: `describe` emits the
architecture configuration as JSON; `evaluate` reads `RepositoryInput` from
stdin and emits one `RuleReport`. Cache locations honor `BUMPER_CACHE_DIR`
unchanged; caches from earlier versions are keyed differently and rebuild once.
