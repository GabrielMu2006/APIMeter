// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "APIMeter",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "APIMeterCore", targets: ["APIMeterCore"]),
        .executable(name: "apimeter", targets: ["PhaseAValidator"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "APIMeterCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "APIMeter",
            exclude: ["App", "UI", "ViewModels", "Window"]
        ),
        .executableTarget(
            name: "PhaseAValidator",
            dependencies: ["APIMeterCore"],
            path: "Tools/PhaseAValidator"
        ),
        .testTarget(
            name: "APIMeterCoreTests",
            dependencies: ["APIMeterCore"],
            path: "Tests/APIMeterCoreTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
