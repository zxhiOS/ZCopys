// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Zcopys",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Zcopys",
            targets: ["Zcopys"]
        )
    ],
    targets: [
        .executableTarget(
            name: "Zcopys",
            path: "Sources/Zcopys",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ZcopysTests",
            dependencies: ["Zcopys"],
            path: "Tests/ZcopysTests"
        )
    ]
)
