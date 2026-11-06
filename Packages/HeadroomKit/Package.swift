// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HeadroomKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "HeadroomKit",
            targets: [
                "HeadroomModel", "UsageKit", "SessionKit", "ContextKit", "SetupKit", "HeadroomStore", "HeadroomUI",
                "HeadroomSamples", "CodexKit", "CopilotKit", "HeadroomShare",
            ]
        ),
        // What the widget extension links (1.1 §5): no kit that reads user folders or talks to the network.
        .library(
            name: "HeadroomWidgetKit",
            targets: ["HeadroomModel", "HeadroomUI", "HeadroomSamples", "HeadroomShare", "HeadroomWidgetUI"]
        ),
        .executable(name: "headroom-dump", targets: ["headroom-dump"]),
        .executable(name: "headroom-render", targets: ["headroom-render"]),
    ],
    targets: [
        .target(name: "HeadroomModel"),
        .target(name: "UsageKit", dependencies: ["HeadroomModel"]),
        .target(name: "SessionKit", dependencies: ["HeadroomModel"]),
        .target(name: "ContextKit", dependencies: ["HeadroomModel"]),
        .target(name: "SetupKit", dependencies: ["HeadroomModel"]),
        // OpenAI Codex limits and sessions from `~/.codex`, read only (1.1 §3).
        .target(name: "CodexKit", dependencies: ["HeadroomModel", "ContextKit"]),
        // GitHub Copilot usage through Headroom's own GitHub App (1.1 §4.1–4.8). Foundation only.
        .target(name: "CopilotKit", dependencies: ["HeadroomModel"]),
        .target(
            name: "HeadroomStore",
            dependencies: ["HeadroomModel", "UsageKit", "SessionKit", "ContextKit", "SetupKit", "CodexKit"]
        ),
        .target(name: "HeadroomUI", dependencies: ["HeadroomModel"]),
        // Made-up snapshots: the app's sample data mode, headroom-render and the store screenshots.
        .target(name: "HeadroomSamples", dependencies: ["HeadroomModel"]),
        // The app-to-widget file in the App Group container (1.1 §5.3).
        .target(name: "HeadroomShare", dependencies: ["HeadroomModel"]),
        // Widget views (1.1 §5.6); imports WidgetKit.
        .target(name: "HeadroomWidgetUI", dependencies: ["HeadroomModel", "HeadroomUI", "HeadroomShare"]),
        .executableTarget(name: "headroom-dump", dependencies: ["HeadroomStore", "CodexKit"]),
        .executableTarget(
            name: "headroom-render",
            dependencies: ["HeadroomUI", "HeadroomModel", "HeadroomSamples", "HeadroomWidgetUI"]
        ),

        .testTarget(name: "HeadroomModelTests", dependencies: ["HeadroomModel"], resources: [.copy("Fixtures")]),
        .testTarget(name: "UsageKitTests", dependencies: ["UsageKit"], resources: [.copy("Fixtures")]),
        .testTarget(name: "SessionKitTests", dependencies: ["SessionKit"], resources: [.copy("Fixtures")]),
        .testTarget(name: "ContextKitTests", dependencies: ["ContextKit"], resources: [.copy("Fixtures")]),
        .testTarget(name: "SetupKitTests", dependencies: ["SetupKit"], resources: [.copy("Fixtures")]),
        .testTarget(name: "CodexKitTests", dependencies: ["CodexKit", "ContextKit"], resources: [.copy("Fixtures")]),
        .testTarget(name: "CopilotKitTests", dependencies: ["CopilotKit"], resources: [.copy("Fixtures")]),
        .testTarget(name: "HeadroomStoreTests", dependencies: ["HeadroomStore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "HeadroomUITests", dependencies: ["HeadroomUI"], exclude: ["Golden"]),
        .testTarget(name: "HeadroomSamplesTests", dependencies: ["HeadroomSamples"]),
        .testTarget(name: "HeadroomShareTests", dependencies: ["HeadroomShare"]),
        .testTarget(name: "HeadroomWidgetUITests", dependencies: ["HeadroomWidgetUI"]),
    ],
    swiftLanguageModes: [.v6]
)

// Copilot CLI sessions (1.1 F3, §4.9) compile only while HEADROOM_COPILOT_CLI is defined. If gate G2 fails, delete
// this define and the app target's (project.yml): S3's code then compiles out, with its tests, and nothing about
// Copilot CLI appears anywhere.
for target in package.targets {
    target.swiftSettings = (target.swiftSettings ?? []) + [.define("HEADROOM_COPILOT_CLI")]
}
