// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "CodeEditor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CodeEditorCore", targets: ["CodeEditorCore"]),
        .library(name: "CodeEditorThemes", targets: ["CodeEditorThemes"]),
        .library(name: "CodeEditorTerminal", targets: ["CodeEditorTerminal"]),
        .library(name: "CodeEditorLSP", targets: ["CodeEditorLSP"]),
        .library(name: "CodeEditorUI", targets: ["CodeEditorUI"]),
        .executable(name: "CodeEditorApp", targets: ["CodeEditorApp"])
    ],
    dependencies: [
        // Provides the NSTextView-backed editor and tree-sitter syntax highlighting.
        .package(url: "https://github.com/CodeEditApp/CodeEditSourceEditor", from: "0.15.2"),
        .package(url: "https://github.com/CodeEditApp/CodeEditLanguages.git", from: "0.1.20"),
        .package(url: "https://github.com/CodeEditApp/CodeEditTextView.git", from: "0.12.1")
    ],
    targets: [
        // MARK: - CodeEditorCore
        .target(
            name: "CodeEditorCore",
            path: "Sources/CodeEditorCore",
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),

        // MARK: - CodeEditorThemes
        .target(
            name: "CodeEditorThemes",
            path: "Sources/CodeEditorThemes",
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),

        // MARK: - CodeEditorTerminal
        .target(
            name: "CodeEditorTerminal",
            path: "Sources/CodeEditorTerminal",
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),

        // MARK: - CodeEditorLSP
        .target(
            name: "CodeEditorLSP",
            path: "Sources/CodeEditorLSP",
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),

        // MARK: - CodeEditorUI
        .target(
            name: "CodeEditorUI",
            dependencies: [
                "CodeEditorCore",
                "CodeEditorThemes",
                "CodeEditorTerminal",
                "CodeEditorLSP",
                .product(name: "CodeEditSourceEditor", package: "CodeEditSourceEditor"),
                .product(name: "CodeEditTextView", package: "CodeEditTextView"),
                .product(name: "CodeEditLanguages", package: "CodeEditLanguages")
            ],
            path: "Sources/CodeEditorUI",
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),

        // MARK: - CodeEditorApp
        .executableTarget(
            name: "CodeEditorApp",
            dependencies: [
                "CodeEditorCore",
                "CodeEditorUI",
                "CodeEditorThemes",
                "CodeEditorTerminal",
                "CodeEditorLSP"
            ],
            path: "Sources/CodeEditorApp",
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        ),

        // MARK: - Tests
        .testTarget(
            name: "CodeEditorTests",
            dependencies: ["CodeEditorCore", "CodeEditorTerminal", "CodeEditorLSP"],
            path: "Tests/CodeEditorTests",
            swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency")]
        )
    ]
)