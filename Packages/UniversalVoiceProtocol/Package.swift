// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UniversalVoiceProtocol",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "UniversalVoiceProtocol",
            targets: ["UniversalVoiceProtocol"]
        ),
    ],
    targets: [
        .target(
            name: "UniversalVoiceProtocol"
        ),
        .testTarget(
            name: "UniversalVoiceProtocolTests",
            dependencies: ["UniversalVoiceProtocol"]
        ),
    ]
)
