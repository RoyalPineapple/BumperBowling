# Default Rule Sets

Bumper Bowling ships a small set of semantic `ComponentRequirement` values. They are not magic presets. Each one is a named composition of `SourceFactRule` atoms, then `Requires(...)` gives that composition a scope and severity.

```text
SourceFactRule -> ComponentRequirement -> scoped Requires(...) -> graph rule -> receipt
```

## Shipped Component Requirements

### `.swiftBasics`

Good default Swift modeling pressure for core code.

```swift
ComponentRequirement(
    .explicitDomainSurfaces,
    .typedIdentity,
    .immutableStoredState
)
```

Lowers to:

- no stored properties explicitly typed as `Any`
- no stored properties explicitly typed as `any ...`
- no stored properties explicitly typed as `String`
- no mutable stored properties

Use it for:

- domain models
- package core types
- shared value types
- code where invalid state should be made harder to construct

Start at `.warning` unless the scope is already clean.

Passes:

```swift
struct User {
    let id: UserID
    let profile: UserProfile
}
```

Fails:

```swift
struct User {
    var id: String
    let payload: Any
    let service: any UserService
}
```

Possible receipts:

- `Stored property id is mutable`
- `Stored property id uses raw String`
- `Stored property payload uses Any`
- `Stored property service uses a broad existential`

### `.functionalCore`

Opinionated functional-style pressure.

```swift
ComponentRequirement(
    .disallowSyntaxConstruct(.assignment),
    .disallowSyntaxConstruct(.loop),
    .disallowSyntaxConstruct(.mutableBinding),
    .disallowSyntaxConstruct(.inoutExpression),
    .disallowSyntaxConstruct(.mutatingDeclaration)
)
```

Lowers to:

- no assignment syntax facts
- no loop syntax facts
- no mutable binding syntax facts
- no `inout` expression syntax facts
- no `mutating` declaration syntax facts

Use it for:

- reducers
- validators
- normalization pipelines
- parser inner loops only when the parser is intentionally modeled as immutable transitions
- deterministic core logic

Do not apply it blindly to app shells, UI code, CLI orchestration, or integration code. Those areas often need controlled imperative glue.

Passes:

```swift
func normalized(_ values: [Int]) -> [Int] {
    values
        .filter { $0 > 0 }
        .map { $0 * 2 }
}
```

Fails:

```swift
func normalized(_ values: [Int]) -> [Int] {
    var result: [Int] = []
    for value in values {
        result.append(value * 2)
    }
    return result
}
```

Possible receipts:

- `Uses imperative construct mutableBinding`
- `Uses imperative construct loop`

### `.parserStateMachine`

Narrow parser/workflow modeling pressure.

```swift
ComponentRequirement(.enumStateMachine)
```

Lowers to:

- require an enum declaration whose name ends in `State` in the configured parser scope

Use it for:

- parsers
- scanners
- workflows with explicit phases
- state transitions where state should carry its data

Usually use this with `RequiresScoped(...)` so only parser files are checked.

Passes:

```swift
enum ParserState {
    case scanning([Token])
    case finished(AST)
}

struct Parser {}
```

Fails:

```swift
struct Parser {
    private var tokens: [Token]
}
```

Possible receipt:

- `Parser file does not declare an enum state machine`

### `.pureDomain`

Convenience composition for highly guarded domain code.

```swift
ComponentRequirement(
    .swiftBasics,
    .functionalCore
)
```

Lowers to all `.swiftBasics` and `.functionalCore` fact-rules.

Use it for:

- small domain kernels
- rules engines
- deterministic policy code
- code that should be easy for agents to edit without crossing architectural lanes

This is intentionally strong. It should be opt-in per component or path.

Passes:

```swift
struct PriceRule {
    let id: RuleID

    func apply(to price: Price) -> Price {
        price.discounted(by: id)
    }
}
```

Fails:

```swift
struct PriceRule {
    var id: String

    mutating func apply(to price: inout Price) {
        price = price.discounted(by: id)
    }
}
```

Possible receipts:

- `Stored property id is mutable`
- `Stored property id uses raw String`
- `Uses imperative construct mutatingDeclaration`
- `Uses imperative construct inoutExpression`
- `Uses imperative construct assignment`

### `.computedState`

Preference for derived state over stored state.

```swift
ComponentRequirement(.noStoredProperties)
```

Lowers to:

- no stored property syntax facts

Use it for:

- selectors
- derived views over state
- stateless validators
- pure transformation modules

This does not prove a value can be computed. It only enforces that SwiftSyntax should not observe stored properties in the configured scope.

Passes:

```swift
enum UserSummary {
    static func displayName(for user: User) -> String {
        "\(user.firstName) \(user.lastName)"
    }
}
```

Fails:

```swift
struct UserSummary {
    let displayName: String
}
```

Possible receipt:

- `Stored property displayName is stored`

## Raw Fact Shorthand

These are smaller building blocks. They are useful directly, and they are also how semantic combinations are built.

### `.typedIdentity`

Passes:

```swift
struct User {
    let id: UserID
}
```

Fails:

```swift
struct User {
    let id: String
}
```

Receipt:

- `Stored property id uses raw String`

### `.explicitDomainSurfaces`

Passes:

```swift
struct Command {
    let payload: CommandPayload
    let handler: CommandHandler
}
```

Fails:

```swift
struct Command {
    let payload: Any
    let handler: any Handler
}
```

Receipts:

- `Stored property payload uses Any`
- `Stored property handler uses a broad existential`

### `.immutableStoredState`

Passes:

```swift
struct Session {
    let id: SessionID
}
```

Fails:

```swift
struct Session {
    var id: SessionID
}
```

Receipt:

- `Stored property id is mutable`

### `.noStoredProperties`

Passes:

```swift
enum UserSort {
    static func ordered(_ users: [User]) -> [User] {
        users.sorted { $0.name < $1.name }
    }
}
```

Fails:

```swift
struct UserSort {
    let cachedUsers: [User]
}
```

Receipt:

- `Stored property cachedUsers is stored`

## Graph Assertions

These are the default architecture assertions Bumper Bowling expects most projects to use:

```swift
Assertions {
    DependencyBoundaries(.error)
    SingleOwner(.error)
    AcyclicDeclaredDependencies(.error)
}
```

### `DependencyBoundaries`

Checks observed component import edges against declared `MayDependOn` and `DoesNotDependOn` edges.

Use it for every repository with more than one component.

### `SingleOwner`

Checks configured component path ownership for overlap.

Use it by default. Ambiguous ownership makes receipts less useful.

### `AcyclicDeclaredDependencies`

Checks declared `MayDependOn` edges for cycles.

Use it by default. Cycles in the declared graph make component lanes harder to reason about.

## Capability Defaults

Capabilities lower to import facts. In 0.0, only module-backed capabilities are shipped.

Recommended component posture:

```swift
Component(.core) {
    MayUse(.foundation)
    DoesNotUse(.testing, .persistence, .networking)
    Requires(.swiftBasics, severity: .warning)
}

Component(.domain) {
    MayUse(.foundation)
    DoesNotUse(.testing, .persistence, .networking, .uiKit, .swiftUI)
    Requires(.swiftBasics, severity: .error)
}

Component(.parser) {
    MayUse(.foundation)
    RequiresScoped(.parserStateMachine, "Sources/**/*Parser.swift", severity: .error)
}
```

The exact components are repository-specific. The default idea is stable: keep test frameworks, persistence, networking, and UI frameworks out of guarded core/domain scopes unless the architecture explicitly says otherwise.

## Full Example

```swift
let configuration = BumperConfiguration {
    Included {
        "Sources"
    }

    Excluded {
        ".build"
        "DerivedData"
    }

    Architecture {
        Component(.core) {
            Owns("Sources/Core")
            Modules("Core")
            MayUse(.foundation)
            DoesNotUse(.testing, .persistence, .networking)
            Requires(.swiftBasics, severity: .warning)
        }

        Component(.domain) {
            Owns("Sources/Domain")
            Modules("Domain")
            MayDependOn(.core)
            MayUse(.foundation)
            DoesNotUse(.testing, .persistence, .networking, .uiKit, .swiftUI)
            Requires(.pureDomain, severity: .error)
        }

        Component(.parser) {
            Owns("Sources/Parsing")
            Modules("Parsing")
            MayDependOn(.core, .domain)
            MayUse(.foundation)
            RequiresScoped(.parserStateMachine, "Sources/Parsing/**/*Parser.swift", severity: .error)
        }
    }

    Assertions {
        DependencyBoundaries(.error)
        SingleOwner(.error)
        AcyclicDeclaredDependencies(.error)
    }
}
```

## Receipts

Semantic rule sets always report raw observed facts. Examples:

- `.typedIdentity` can report `Stored property id uses raw String`.
- `.explicitDomainSurfaces` can report `Stored property payload uses Any`.
- `.immutableStoredState` can report `Stored property state is mutable`.
- `.computedState` can report `Stored property fullName is stored`.
- `.functionalCore` can report `Uses imperative construct assignment`.
- `.parserStateMachine` can report `Parser file does not declare an enum state machine`.

That is the contract: users interact with semantic shorthand, while Bumper Bowling explains violations with SwiftSyntax facts.
