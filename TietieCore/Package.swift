// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TietieCore",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "TietieCore", targets: ["TietieCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "TietieCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(name: "TietieCoreTests", dependencies: ["TietieCore"]),
    ],
    swiftLanguageModes: [.v5]
)
