# Scopes, Matching, And Severity

[Built-ins index](README.md)

## File Scopes

`RuleScope` selects files:

| Scope | Selection |
| --- | --- |
| `.repository` | Every included file. |
| `.productionSources` | Files outside `Tests/`. |
| `.component(.core)` | Files assigned to one component. |
| `.under("Sources/Core")` | Files under one path. |
| `.files(paths)` | An explicit set of files. |

Combine scopes with `.union(_:)`, `.intersecting(_:)`, and `.excluding(_:)`.
A repository also defines a scope with `RuleScope { descriptor in ... }`.

## Lexical Scopes

`SyntaxScope` selects nodes inside each file:

| Scope | Selection |
| --- | --- |
| `.anywhere` | Every matching node. |
| `.fileScope` | File-level declarations. |
| `.typeMembers` | Type members. |
| `.local` | Local declarations. |
| `.protocolMembers` | Protocol members. |
| `.enclosed(in: "Store")` | Nodes inside a named nominal declaration. |
| `.insideFunction(matching: "load")` | Nodes inside a matching function. |

`SyntaxScope` supports the same union, intersection, and exclusion operations.

## String Matching

A string literal creates an exact `StringMatcher`. Other constructors select
another matching mode:

| Matcher | Selection |
| --- | --- |
| `.exact("State")` | The complete spelling equals `State`. |
| `.contains("State")` | The spelling contains `State`. |
| `.prefix("make")` | The spelling starts with `make`. |
| `.suffix("Feature")` | The spelling ends with `Feature`. |
| `.regex("^legacy[A-Z]")` | The spelling matches an explicit regular expression. |

## Severity

Rules use `.off`, `.note`, `.warning`, or `.error` severity. `.error` controls
the failing exit status. The other active severities remain in the report.

Next: [Built-in facts](facts.md)
