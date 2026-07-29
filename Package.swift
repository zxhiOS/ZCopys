// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "mac_tool",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "mac_tool",
            targets: ["mac_tool"]
        )
    ],
    targets: [
        .executableTarget(
            name: "mac_tool",
            path: "Sources/mac_tool"
        ),
        .testTarget(
            name: "mac_toolTests",
            dependencies: ["mac_tool"],
            path: "Tests/mac_toolTests"
        )
    ]
)
