# SwiftSyntax Fact Catalog

Bumper Bowling wants the full SwiftSyntax-observable fact vocabulary, but it should not eagerly copy the whole SwiftSyntax tree into `ArchitectureGraph`.

The model is:

```text
SwiftSyntax node/token/trivia -> raw fact -> scoped rule -> semantic shorthand -> finding/report
```

Every fact in this catalog must satisfy two constraints:

- SwiftSyntax can observe it without type checking.
- Bumper Bowling can report it as evidence for a finding.

Bumper Bowling does not mirror SwiftSyntax's node types. It stores SwiftSyntax's own `SyntaxKind` values for compact graph checks and adds computed `bumper` views to concrete SwiftSyntax nodes for local facts.

## Current 0.1 Facts

### File Facts

- relative file path

Configured ownership adds:

- owning component
- included path membership
- excluded path membership

### Import Facts

- imported module name

Derived graph facts:

- module import edge
- component import edge, when an imported module maps to a configured component

### Declaration Facts

- declaration kind
- declaration name
- syntactic access level for `public` and `open`
- public declaration attribute names

Current declaration kinds:

- actor
- class
- enum
- function
- protocol
- struct
- variable

### Stored Property Facts

- stored property exists
- stored property name
- explicit type annotation, when present
- mutability from `let` or `var`

Current stored-property fact-rules:

- stored property is present
- stored property is mutable
- stored property is explicitly typed as `Any`
- stored property is explicitly typed as `any ...`
- stored property is explicitly typed as `String`

### Enum Facts

- enum declaration name

Current enum fact-rule:

- parser scope declares an enum whose name ends in `State`

### Syntax Construct Facts

- assignment
- loop
- mutable binding
- `inout` expression
- `mutating` declaration

### Syntax Kind Facts

- SwiftSyntax `SyntaxKind` values observed while traversing parsed source
- selected spelling for report-worthy kinds such as declarations, imports, attributes, modifiers, types, patterns, and literals
- broad fact family for grouping observed syntax into declarations, expressions, statements, type syntax, patterns, macros, concurrency syntax, literals, and tokens

Current syntax-kind fact-rule:

- require a `SyntaxKind` in a configured scope
- disallow a `SyntaxKind` in a configured scope

Examples:

```swift
RequireSyntax(.enumDecl)
DisallowSyntax(.forceUnwrapExpr)
```

These use SwiftSyntax's `SyntaxKind` directly.

### Computed Node Views

Some facts are better inferred from real SwiftSyntax node types than from raw kind membership. Bumper Bowling exposes those as computed views:

- `SyntaxProtocol.bumper.kind`
- `SyntaxProtocol.bumper.spelling`
- `SyntaxProtocol.bumper.isA(_:)`
- `SyntaxProtocol.bumper.hasAncestor(_:)`
- `ImportDeclSyntax.bumper.importedModuleName`
- `AttributeSyntax.bumper.attributeName`
- `IdentifierTypeSyntax.bumper.typeName`
- `FunctionDeclSyntax.bumper.isMutatingDeclaration`
- `PatternBindingSyntax.bumper.identifierName`
- `PatternBindingSyntax.bumper.explicitTypeName`
- `PatternBindingSyntax.bumper.hasAccessorBlock`
- `VariableDeclSyntax.bumper.isMutableBinding`
- `VariableDeclSyntax.bumper.isImmutableBinding`
- `VariableDeclSyntax.bumper.isMemberDeclaration`
- `VariableDeclSyntax.bumper.bindingNames`
- `VariableDeclSyntax.bumper.explicitTypeNames`
- `VariableDeclSyntax.bumper.storedProperties`

These views do not add stored state to SwiftSyntax nodes. They are pure computations over syntax and immediate syntax context.

## Full SwiftSyntax Fact Vocabulary

These are the fact families Bumper Bowling should be able to grow into. The observed `SyntaxKind` set is recorded in 0.1, but only selected facts are normalized into first-class architecture graph fields.

### Source File And Trivia

- source file path
- shebang
- comments
- documentation comments
- whitespace and newlines
- source locations
- disabled/active conditional compilation regions

Most trivia facts should stay out of architecture rules unless they directly support a finding that SwiftLint does not already own.

### Imports

- imported module path
- import kind, such as `struct`, `class`, `enum`, `protocol`, `func`, `var`, or `typealias`
- exported imports
- implementation-only imports, when represented in source syntax
- import attributes

### Declarations

- declaration kind
- declaration name
- access modifiers
- declaration modifiers
- attributes
- generic parameters
- generic requirements
- inheritance clauses
- member declarations
- nested declaration relationships

Declaration kinds include:

- actor
- associated type
- class
- deinitializer
- enum
- enum case
- extension
- function
- import
- initializer
- macro
- operator
- precedence group
- protocol
- struct
- subscript
- type alias
- variable

### Type Syntax

- identifier type
- member type
- optional type
- implicitly unwrapped optional type
- array type
- dictionary type
- tuple type
- function type
- attributed type
- composition type
- `some` type
- `any` type
- metatype type
- pack expansion type
- missing type syntax

Syntax can say what type annotation was written. It cannot prove inferred type or type identity.

### Pattern And Binding Syntax

- `let` binding
- `var` binding
- identifier pattern
- tuple pattern
- wildcard pattern
- enum case pattern
- optional pattern
- expression pattern
- typed pattern
- value binding pattern

### Statement Syntax

- code block
- `if`
- `guard`
- `switch`
- `for`
- `while`
- `repeat`
- `do`
- `defer`
- `return`
- `throw`
- `break`
- `continue`
- `fallthrough`
- `yield`
- `then`
- `discard`

### Expression Syntax

- assignment
- sequence expression
- function call
- member access
- subscript call
- closure
- key path
- literals
- tuple expression
- array expression
- dictionary expression
- `try`
- `await`
- `as` / `as?` / `as!`
- `is`
- force unwrap
- optional chaining
- ternary expression
- macro expansion expression
- `inout` expression
- operator expression

### Closure Facts

- closure exists
- capture list
- closure parameters
- `async`
- `throws`
- explicit return type
- shorthand argument usage

### Concurrency Syntax

- `async` declarations
- `await` expressions
- `throws` / `rethrows`
- actor declarations
- global actor attributes such as `@MainActor`
- `nonisolated`
- `isolated` parameters
- `Task` construction if expressed as syntax Bumper Bowling chooses to recognize

Syntax can observe concurrency spelling. It cannot prove isolation correctness.

### Macro Syntax

- freestanding macro expansion
- attached macro attribute
- macro name
- macro arguments

Syntax can observe macro use. It cannot know the expanded code in the 0.1 lane.

### Literal Facts

- string literal
- integer literal
- float literal
- boolean literal
- nil literal
- regex literal
- array literal
- dictionary literal

### Attribute And Modifier Facts

- attribute name
- attribute arguments
- declaration modifier name
- detail token for modifiers that have one

Examples:

- `public`
- `open`
- `private`
- `fileprivate`
- `internal`
- `static`
- `class`
- `final`
- `mutating`
- `nonmutating`
- `override`
- `required`
- `convenience`
- `lazy`
- `weak`
- `unowned`
- `indirect`

## Not SwiftSyntax Facts

These require compiler or build-system knowledge:

- inferred types
- overload resolution
- symbol resolution
- protocol conformance truth
- actual module dependency truth after build settings
- target membership
- macro expansion semantics
- data flow
- effect flow
- runtime behavior
- business invariants

Those can belong to a future compiler-backed analysis lane, not the SwiftSyntax fact catalog. The current request list lives in [COMPILER_REQUESTS.md](COMPILER_REQUESTS.md).

## Extraction Rule

Do not add a fact just because SwiftSyntax can expose it. Add it when all are true:

- a rule or semantic shorthand can use it
- it can be represented as a stable typed value
- it can be scoped by path/component
- it can produce deterministic evidence for a finding

The catalog can be broad. The architecture graph should stay lean.
