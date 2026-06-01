// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Detto",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/Gremble-io/gremble-voice.git", revision: "282c3859347fe9b37a1c3f1d9ac4c30a9ba8a598"),
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
