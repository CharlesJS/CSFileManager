// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "CSFileManager",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6),
        .macCatalyst(.v13)
    ],
    products: [
        .library(
            name: "CSFileManager",
            targets: ["CSFileManager"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/CharlesJS/CSErrors", from: "1.2.2"),
        .package(url: "https://github.com/CharlesJS/CSFileInfo", from: "0.3.1")
    ],
    targets: [
        .target(
            name: "CSFileManager",
            dependencies: ["CSErrors", "CSFileInfo"]
        ),
        .testTarget(
            name: "CSFileManagerTests",
            dependencies: ["CSFileManager"]
        ),
    ]
)
