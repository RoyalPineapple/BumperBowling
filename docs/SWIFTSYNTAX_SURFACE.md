# SwiftSyntax Surface

Bumper Bowling validates declared codebase shape against selected SwiftSyntax facts.

SwiftSyntax can represent the full Swift source tree. Bumper Bowling does not copy that tree and does not expose an infinitely configurable query language. It records selected raw facts, projects them into `ArchitectureGraph`, then runs lean mathematical checks over that graph.

See [FACT_CATALOG.md](FACT_CATALOG.md) for the broader SwiftSyntax fact vocabulary Bumper Bowling can grow into.

## Current Facts

### Files

- Relative file path.
- Owning component, derived from configured path ownership.

### Imports

- Explicit imported module names.
- Module import edges from source file to imported module.
- Component import edges when an imported module maps to a configured component.

### Declarations

- Syntactic `public` and `open` declarations.
- Declaration kind: actor, class, enum, function, protocol, struct, variable.
- Declaration name.
- Attribute names attached to public declarations.

### Stored Properties

- Stored property name.
- Explicit type annotation, when present.
- Mutability from `let` or `var`.

No type inference is performed. A stored property without an explicit type annotation does not have a known type fact.

### Enums

- Enum declaration names.
- Used by state-machine assertions such as requiring parser files to declare an enum whose name ends in `State`.

### Imperative Constructs

Bumper currently records selected syntax facts:

- assignment
- loop
- mutable binding
- `inout` expression
- `mutating` declaration

These facts are descriptive. They become policy only when the DSL declares a lane such as:

```swift
Disallows(.assignment, .loop, .mutableBinding)
```

## Configured Facts

The DSL supplies the facts SwiftSyntax cannot know by itself:

- included paths
- excluded paths
- component names
- component path ownership
- component module aliases
- allowed component dependency edges
- forbidden component dependency edges
- allowed capabilities
- assertion severities
- scoped modeling assertions

## Graph Projection

`ArchitectureGraph` is the receipt surface rules operate on. In 0.0 it contains:

- source files
- component nodes
- module import edges
- component import edges

Source files carry their observed imports, declarations, stored properties, enum names, and imperative constructs.

Rules operate on that projection with deterministic operations: path scope, set membership, graph edge checks, and cycle detection.

Semantic DSL shorthand does not add hidden facts. It composes `SourceFactRule` atoms, then lowers into these same graph operations.

## Not Known

Bumper Bowling does not know:

- inferred types
- symbol resolution
- overload resolution
- true build target membership
- macro expansion semantics
- compiler-validated public API surface
- protocol conformance truth
- runtime behavior
- data flow or effect flow
- business invariants

If a rule needs those facts, it does not belong in the SwiftSyntax-only 0.0 lane.

## Rule

Every finding should have a receipt:

```text
observed graph fact + declared lane = mismatch
```

If Bumper cannot show the observed fact, it should not report the violation.
