// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "KVStore",
    platforms: [
        .iOS(.v12)
    ],
    products: [
        .library(name: "KVStore", targets: ["KVStore"])
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.14.1")
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
