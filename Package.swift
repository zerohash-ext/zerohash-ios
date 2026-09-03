// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ZerohashSDK",
    platforms: [
        .iOS(.v17)
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
            dependencies: [],
            resources: [
                .process("Resources/Media.xcassets"),
                .process("Automation/dom-helpers.js"),
                .process("Automation/telemetry.js"),
                .process("Automation/setup-execution-context.js"),
                .process("Platforms/Coinbase/auth-status.js"),
                .process("Platforms/Coinbase/auth-detect-unsupported-2fa.js"),
                .process("Platforms/Coinbase/auth-signup.js"),
                .process("Platforms/Coinbase/auth-hide-social.js"),
                .process("Platforms/Coinbase/auth-choose-2fa-method.js"),
                .process("Platforms/Coinbase/get-deposit-address.js"),
                .process("Platforms/Coinbase/coinbase-idv-gate.js"),
                .process("Platforms/Coinbase/get-balance.js"),
                .process("Platforms/Coinbase/coinbase-balance-queries.js"),
                .process("Platforms/Coinbase/withdraw.js"),
            ]
        ),
        .testTarget(
            name: "ZerohashSDKTests",
            dependencies: ["ZerohashSDK"]
        ),
    ]
)
