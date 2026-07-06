// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ZerohashSDK",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "ZerohashSDK",
            targets: ["ZerohashSDK"]
        ),
    ],
    targets: [
        .target(
            name: "ZerohashSDK",
            dependencies: []
        ),
        .testTarget(
            name: "ZerohashSDKTests",
            dependencies: ["ZerohashSDK"]
        ),
    ]
)
