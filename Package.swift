// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BumperBowling",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "BumperBowlingCore", targets: ["BumperBowlingCore"]),
        .executable(name: "bumper", targets: ["BumperBowling"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0"),
    ],
    targets: [
        .target(
            name: "BumperBowlingCore",
            dependencies: [
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
            ],
            swiftSettings: strictConcurrencySettings
        ),
        .executableTarget(
            name: "BumperBowling",
            dependencies: ["BumperBowlingCore"],
            swiftSettings: strictConcurrencySettings
        ),
        .testTarget(
            name: "BumperBowlingCoreTests",
            dependencies: ["BumperBowlingCore"],
            swiftSettings: strictConcurrencySettings
        ),
    ]
)

let strictConcurrencySettings: [SwiftSetting] = [
    .enableUpcomingFeature("StrictConcurrency"),
    .enableUpcomingFeature("InferSendableFromCaptures"),
]
