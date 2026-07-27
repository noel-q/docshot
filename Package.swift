// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DocShot",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "DocShot",
            targets: ["DocShot"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "DocShot",
            dependencies: [],
            path: "Sources/DocShot",
            exclude: ["Info.plist"],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "DocShotTests",
            dependencies: ["DocShot"],
            path: "Tests/DocShotTests"
        )
    ]
)
