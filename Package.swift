// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "configdirector-swift-sdk",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
    ],
    products: [
        .library(name: "ConfigDirector", targets: ["ConfigDirector"]),
        .library(name: "ConfigDirectorTesting", targets: ["ConfigDirectorTesting"]),
    ],
    targets: [
        .target(
            name: "ConfigDirector",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "ConfigDirectorTesting",
            dependencies: ["ConfigDirector"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ConfigDirectorTests",
            dependencies: ["ConfigDirector"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ConfigDirectorTestingTests",
            dependencies: ["ConfigDirectorTesting"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
