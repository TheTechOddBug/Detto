// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Detto",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/Gremble-io/gremble-voice.git", revision: "139cea97f6a89a8d5c86556c93527db2efa39a8c"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
    ],
    targets: [
        .executableTarget(
            name: "Detto",
            dependencies: [
                .product(name: "GrembleVoiceParakeet", package: "gremble-voice"),
                .product(name: "GrembleVoiceCore", package: "gremble-voice"),
                .product(name: "GrembleVoiceRefinement", package: "gremble-voice"),
                .product(name: "GrembleVoiceEngine", package: "gremble-voice"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Detto",
            exclude: ["Info.plist", "Detto.entitlements", "Assets"]
        ),
        .testTarget(
            name: "DettoTests",
            dependencies: ["Detto"],
            path: "Tests/DettoTests"
        ),
    ]
)
