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
    dependencies: [
        .package(path: "Packages/ClipboardKit")
    ],
    targets: [
        .executableTarget(
            name: "DocShot",
            dependencies: [.product(name: "ClipboardKit", package: "ClipboardKit")],
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
            dependencies: ["DocShot", .product(name: "ClipboardKit", package: "ClipboardKit")],
            path: "Tests/DocShotTests"
        )
    ]
)
