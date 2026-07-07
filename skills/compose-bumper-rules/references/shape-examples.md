# Shape Examples

## Inline

Use for tiny one-off rule names:

```swift
extension ComponentRequirement {
    static let noStateBags = ComponentRequirement(
        .noOptionalStoredProperties,
        .noBoolStoredProperties
    )
}
```

## Repo-Local `.bumper/Sources`

```text
.bumper/
  Sources/
    HouseStyle.swift
```

`HouseStyle.swift`:

```swift
import BumperBowlingCore

extension ComponentShape {
    static let appBoundary = ComponentShape {
        MayUse(.foundation, .swiftUI)
        DoesNotUse(.testing)
        Requires(.explicitDomainSurfaces, severity: .warning)
    }
}
```

## SwiftPM `.bumper/Package.swift`

Use when rule vocabulary should be reusable as a package:

```text
.bumper/
  Package.swift
  Sources/
    BumperRules/
      Rules.swift
```

`Package.swift` must expose a `BumperRules` library product:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BumperRules",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "BumperRules", targets: ["BumperRules"])
    ],
    dependencies: [
        .package(path: "../path/to/BumperBowling")
    ],
    targets: [
        .target(
            name: "BumperRules",
            dependencies: [
                .product(name: "BumperBowlingCore", package: "BumperBowling")
            ]
        )
    ]
)
```

Then in `BumperBowling.swift`:

```swift
import BumperBowlingCore
import BumperRules
```
