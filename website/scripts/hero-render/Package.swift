// swift-tools-version: 6.0
import PackageDescription

// Renders the website's hero panel and social-card pill from synthetic data (see website/README.md).
let package = Package(
    name: "hero-render",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../../Packages/HeadroomKit")],
    targets: [
        .executableTarget(name: "hero-render", dependencies: [.product(name: "HeadroomKit", package: "HeadroomKit")]),
    ],
    swiftLanguageModes: [.v6]
)
