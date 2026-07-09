# Parallel Rule Graph

Bumper Bowling should have one rule-evaluation pipeline:

1. Discover source inputs.
2. Parse each Swift file once.
3. Project one immutable `RuleGraph`.
4. Schedule built-in and custom rule jobs over that graph.
5. Execute jobs in parallel.
6. Merge findings deterministically.

Raw SwiftSyntax should be an escape hatch, not the default custom-rule path. The normal contract for built-in and custom rules should be typed, `Codable`, `Sendable` graph data.

## State Machine

```swift
enum LintRunState {
    case idle
    case preparingRules(ArchitectureConfiguration)
    case scanningSources(LintPreparedRules)
    case evaluatingRules(LintEvaluationPlan)
    case collectingFindings(LintRuleEvaluation)
    case reporting(LintRunResult)
    case failed(LintRunFailure)
}
```

Reducers own lifecycle transitions. Boundary code performs effects: scanning, rule execution, worker process launch, and report output.

## Rule Graph

`RuleGraph` should be the durable artifact passed to every rule lane:

```swift
public struct RuleGraph: Codable, Sendable {
    public let schemaVersion: Int
    public let files: [RuleGraphFile]
    public let components: [RuleGraphComponent]
    public let dependencyEdges: [RuleGraphDependencyEdge]
}
```

It should contain stable facts, not live SwiftSyntax nodes:

- path, component, imports
- declarations, access, attributes, ancestry
- stored properties and type spellings
- syntax kinds and selected spellings
- ownership and dependency edges
- source locations

## Scheduler

Rules become jobs:

```swift
struct RuleJob: Sendable {
    let ruleID: RuleID
    let shard: RuleShard
}

enum RuleShard: Sendable {
    case project
    case files([RelativeFilePath])
}
```

The scheduler can submit all jobs by default. A configured `maxConcurrentRuleJobs` bounds active jobs when a repo wants CI protection.

## Worker Pool

The default custom-rule worker stays process-isolated:

- Main process writes the graph artifact once.
- Main process launches sandboxed workers with `{ graphPath, ruleIDs, shard }`.
- Workers decode or memory-map the graph, run assigned predicates, emit findings JSON.
- Main process sorts findings by path, location, rule id, severity, and message.

This preserves arbitrary Swift rule isolation without reparsing source for normal custom rules.

## Raw Syntax Escape Hatch

`CustomSyntaxRule` remains available for rules that truly need SwiftSyntax. It should run in a separate lane that receives source shards and parses in the worker. It is powerful but slower, and should not be the default authoring surface.
