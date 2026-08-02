# Components

[Built-ins index](README.md)

A component gives source paths a repository-defined name. Its elements add
ownership, dependency, capability, and source-shape policy.

| Element | Declares |
| --- | --- |
| `Owns("Sources/Core")` | The component owns a source path. |
| `Paths("Sources/Core")` | The component owns a source path. This is an alternate builder spelling. |
| `Modules("Core")` | An imported module represents the component. |
| `MayDependOn(.core)` | The component permits a declared dependency. |
| `DoesNotDependOn(.legacy)` | The component forbids a declared dependency. |
| `MayUse(.foundation)` | The component permits a platform capability. |
| `DoesNotUse(.uiKit)` | The component forbids a capability or module. |
| `Requires(.typedIdentity)` | Owned files meet a source requirement. |
| `RequiresScoped(.enumStateMachine, "Sources/Parser")` | Selected paths meet a source requirement. |
| `Requires(.typedIdentity, except: [...])` | Owned files meet a requirement outside excluded paths. |
| `Disallows(.loop)` | Owned files exclude an imperative construct. |
| `Disallows(.loop, in: "Sources/Core")` | Selected paths exclude an imperative construct. |
| `Declares("State")` | Owned files contain a matching public declaration. |
| `Does(ContainSyntax(.enumDecl))` | Owned files contain matching syntax. |
| `DoesNot(ContainSyntax(.classDecl))` | Owned files exclude matching syntax. |
| `Applies(.domain)` | The component inserts a reusable `ComponentShape`. |

Example:

```swift
Component(.catalog) {
    Owns("Sources/Catalog")
    Modules("Catalog")
    MayDependOn(.core)
    MayUse(.foundation)
    Requires(.typedIdentity, .immutableStoredState)
}
```

`Owns` provides the default path scope for requirements in that component.
`RequiresScoped` replaces that default for one requirement.

## Platform Capabilities

| Capability | Modules |
| --- | --- |
| `.foundation` | `Foundation` |
| `.swiftUI` | `SwiftUI` |
| `.uiKit` | `UIKit` |
| `.persistence` | `CoreData`, `SwiftData` |
| `.networking` | `FoundationNetworking` |
| `.testing` | `XCTest`, `Testing` |

`MayUse` creates forbidden-import rules for known modules outside its selected
capabilities. `DoesNotUse` creates direct forbidden-import rules.

## Compose Components

A `ComponentShape` groups component elements:

```swift
extension ComponentShape {
    static let domain = ComponentShape {
        MayUse(.foundation)
        DoesNotUse(.uiKit, .testing)
        Requires(.typedIdentity, .immutableStoredState)
    }
}
```

`Applies(.domain)` inserts those elements into the current component. The
component still declares its own name and paths.

Next: [Component requirements](requirements.md)
