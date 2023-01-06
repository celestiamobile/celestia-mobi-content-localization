// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CelestiaMobiContentLocalization",
    platforms: [
        .macOS("12.0"), .iOS("15.0"), .watchOS("8.0"), .tvOS("15.0")
    ],
    dependencies: [
        .package(url: "https://github.com/levinli303/OpenCloudKit.git", from: "0.8.18"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
    ],
    targets: [
        .target(
            name: "Parser",
            dependencies: [
                .product(name: "OpenCloudKit", package: "OpenCloudKit"),
            ]
        ),
        .executableTarget(
            name: "UploaderApp",
            dependencies: [
                .target(name: "Parser"),
                .product(name: "OpenCloudKit", package: "OpenCloudKit"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "SynchronizerApp",
            dependencies: [
                .target(name: "Parser"),
                .product(name: "OpenCloudKit", package: "OpenCloudKit"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ]
)
