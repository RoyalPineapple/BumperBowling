# Graph Assertions

[Built-ins index](README.md)

Graph assertions validate relationships across declared components.

| Assertion | Validation | Example failure | Lower-level fact |
| --- | --- | --- | --- |
| `DependencyBoundaries(.error)` | Observed component imports follow declared dependency edges. | CLI imports undeclared component Database. | Component import edges |
| `SingleOwner(.error)` | A source path has one component owner. | Core and App both own one file. | Component path configuration |
| `AcyclicDeclaredDependencies(.error)` | The declared component dependency graph has no cycle. | Core and App depend on each other. | Declared dependency edges |
| `NoDirectStringMatching(.error, paths: [...])` | Selected paths exclude direct string-match constructs. | A selected file compares a value directly with a string literal. | Imperative construct facts |

Group assertions with `AssertionShape`:

```swift
extension AssertionShape {
    static let projectGraph = AssertionShape {
        DependencyBoundaries(.error)
        SingleOwner(.error)
        AcyclicDeclaredDependencies(.error)
    }
}
```

Apply the group in the project rule block:

```swift
Rules {
    ApplyAssertions(.projectGraph)
}
```

Next: [Standard rule shapers](shapers.md)
