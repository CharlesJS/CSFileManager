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
        .package(
            url: "https://github.com/CharlesJS/CSErrors",
            from: "2.0.0",
            traits: [
                .trait(name: "Foundation", condition: .when(traits: ["Foundation"]))
            ]
        ),
        .package(
            url: "https://github.com/CharlesJS/CSFileInfo",
            from: "0.5.0",
            traits: [
                .trait(name: "Foundation", condition: .when(traits: ["Foundation"]))
            ]
        ),
        .package(url: "https://github.com/CharlesJS/SyncPolyfill", from: "0.1.0"),
    ],
    targets: [
        .target(
            name: "CSFileManager",
            dependencies: [
                "CSErrors",
                "CSFileInfo",
                "SyncPolyfill",
            ]
        ),
        .testTarget(
            name: "CSFileManagerTests",
            dependencies: [
                "CSFileManager",
                "CSFileInfo",
            ]
        ),
    ]
)
