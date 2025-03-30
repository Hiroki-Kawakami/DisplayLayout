// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DisplayLayout",
    platforms: [
        .macOS(.v10_15),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.4"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0"),
        .package(url: "https://github.com/FullQueueDeveloper/StaticMemberIterable.git", from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "DisplayLayoutBridge",
            path: "Bridge",
            publicHeadersPath: "."
        ),
        .executableTarget(
            name: "DisplayLayout",
            dependencies: [
                "DisplayLayoutBridge",
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "StaticMemberIterable", package: "StaticMemberIterable"),
            ],
            path: "Sources",
            linkerSettings: [
                .linkedFramework("CoreDisplay", .when(platforms: [.macOS])),
            ]
        )
    ]
)
