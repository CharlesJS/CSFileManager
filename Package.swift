// swift-tools-version: 5.9

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
        .library(
            name: "CSFileManager+Foundation",
            targets: ["CSFileManager_Foundation"]
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
        .target(
            name: "CSFileManager_Foundation",
            dependencies: ["CSFileManager"]
        ),
        .testTarget(
            name: "CSFileManagerTests",
            dependencies: ["CSFileManager", "CSFileManager_Foundation"]
        ),
    ]
)
