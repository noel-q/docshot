// swift-tools-version: 6.0
import PackageDescription

// Clipboard history logic for DocShot (plan section 4.1). Pure logic and storage, no AppKit,
// no third-party dependencies: SQLite and CryptoKit come from the system.
let package = Package(
    name: "ClipboardKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ClipboardKit", targets: ["ClipboardKit"])
    ],
    targets: [
        .target(name: "ClipboardKit"),
        .testTarget(name: "ClipboardKitTests", dependencies: ["ClipboardKit"])
    ]
)
