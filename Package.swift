// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OM0RX-xCat",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "XCatCore", targets: ["XCatCore"]),
        .executable(name: "OM0RX-xCat", targets: ["OM0RXXCatApp"]),
    ],
    targets: [
        .target(name: "XCatCore"),
        .executableTarget(
            name: "OM0RXXCatApp",
            dependencies: ["XCatCore"]
        ),
        .testTarget(
            name: "XCatCoreTests",
            dependencies: ["XCatCore"]
        ),
    ]
)
