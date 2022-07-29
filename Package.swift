// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LugmaKit",
    products: [
        .library(
            name: "LugmaKit",
            targets: ["LugmaKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.9.0"),
        .package(url: "https://github.com/vapor/websocket-kit.git", from: "2.0.0"),
        .package(url: "https://github.com/rexmas/JSONValue.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "LugmaKit",
            dependencies: [
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "WebSocketKit", package: "websocket-kit"),
                .product(name: "JSONValueRX", package: "JSONValue"),
            ]),
        .testTarget(
            name: "LugmaKitTests",
            dependencies: ["LugmaKit"]),
    ]
)
