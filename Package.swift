// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "CSFileManager",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6),
        .macCatalyst(.v13),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "CSFileManager",
            targets: ["CSFileManager"]
        ),
    ],
    traits: [
        "Foundation"
    ],
    dependencies: [
        .package(url: "https://github.com/CharlesJS/CSErrors", from: "2.0.0", traits: [
            .trait(name: "Foundation", condition: .when(traits: ["Foundation"]))
        ]),
        .package(url: "https://github.com/CharlesJS/CSFileInfo", from: "0.6.4", traits: [
            .trait(name: "Foundation", condition: .when(traits: ["Foundation"]))
        ]),
        .package(url: "https://github.com/CharlesJS/SyncPolyfill", from: "0.1.2"),
        .package(url: "https://github.com/CharlesJS/test-helpers.git", from: "0.3.2"),
    ],
    targets: [
        .systemLibrary(
            name: "CSFileManager_CShims",
            providers: [
                .apt(["uuid-dev"]),
            ]
        ),
        .target(
            name: "CSFileManager",
            dependencies: [
                "CSErrors",
                "CSFileInfo",
                "SyncPolyfill",
                .targetItem(name: "CSFileManager_CShims", condition: .when(platforms: [.linux]))
            ]
        ),
        .testTarget(
            name: "CSFileManagerTests",
            dependencies: [
                "CSFileManager",
                "CSFileInfo",
                .product(name: "DiskImageHelper", package: "test-helpers")
            ]
        ),
    ]
)
