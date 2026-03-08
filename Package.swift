// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KVStore",
    platforms: [
        .iOS(.v12),
        .macOS(.v10_15)
    ],
    products: [
        .library(name: "KVStore", targets: ["KVStore"])
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", exact: "0.15.3")
    ],
    targets: [
        .target(
            name: "KVStore",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift")
            ],
            path: "Sources/KVStore"
        ),
        .testTarget(
            name: "KVStoreTests",
            dependencies: ["KVStore"],
            path: "Tests/KVStoreTests"
        )
    ]
)
