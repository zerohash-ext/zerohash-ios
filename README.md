# zerohash-ios

![Swift](https://img.shields.io/badge/Swift-6.0%2B-orange.svg)
![Platform](https://img.shields.io/badge/Platform-iOS%2014%2B-blue.svg)
![SPM Compatible](https://img.shields.io/badge/Swift%20Package%20Manager-compatible-brightgreen.svg)

A Swift SDK for seamless integration with the [zerohash Fund](https://docs.zerohash.com) product.

The SDK exposes the Fund flow that can be presented from your iOS application:

- **Fund** — account funding / pay-to-settle flow

## Features

- **Fund flow** — full account-funding experience exposed through a single SDK
- **Secure WebView bridge** — bidirectional JS ↔ native messaging over a hardened `WKWebView`
- **Theme Support** — Light, dark, and system theme options to match your app's design
- **Real-time Event Callbacks** — Typed callbacks for the Fund flow
- **Multiple Environments** — Sandbox and production environments
- **Type-Safe** — Full Swift type safety with comprehensive error handling

## Requirements

- iOS 14+
- Swift 6.0+
- Xcode 15.3+

## Installation

### Swift Package Manager

#### Using Xcode

1. In Xcode, select **File > Add Package Dependencies...**
2. Enter the repository URL: `https://github.com/zerohash/zerohash-ios`
3. Select the version rule you want to use (we recommend up to next major)
4. Click **Add Package**

#### Using Package.swift

Add ZerohashSDK as a dependency in your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/zerohash/zerohash-ios", from: "1.0.0")
]
```

Then add `ZerohashSDK` to your target's dependencies:

```swift
targets: [
    .target(
        name: "YourApp",
        dependencies: ["ZerohashSDK"]
    )
]
```

## Getting Started

### Import the SDK

```swift
import ZerohashSDK
```

### Obtain a JWT Token

Before presenting the Fund flow, you'll need to obtain a JWT token from
your backend. This token authenticates the end user with the zerohash
platform.

> 📘 **Note:** For detailed instructions on obtaining JWT tokens, please refer to the [zerohash documentation](https://docs.zerohash.com).

## Usage

### Fund

The Fund app handles account funding and pay-to-settle. Use `onFund` to
react to deposit events.

```swift
import UIKit
import ZerohashSDK

class FundViewController: UIViewController {

    private var fundSession: ZerohashFundSession?

    @IBAction func startFundTapped(_ sender: UIButton) {
        let callbacks = FundCallbacks(
            onClose: { print("Fund closed") },
            onError: { error in
                print("Fund error \(error.code): \(error.message)")
            },
            onEvent: { event in
                print("Fund event: \(event.type)")
            },
            onFund: { fund in
                if fund.success {
                    print("✅ Deposit processed — status: \(fund.status ?? "unknown")")
                } else {
                    print("⏳ Deposit status: \(fund.status ?? "unknown")")
                }
            }
        )

        fundSession = ZerohashSDK.configureFund(
            jwt: "your-jwt-token",
            environment: .production,
            theme: .system,
            callbacks: callbacks
        )

        fundSession?.present(from: self)
    }
}
```

## API Reference

### ZerohashSDK

The main entry point for the SDK.

#### `configureFund(jwt:environment:theme:callbacks:)`

Configures a Fund session that can be presented later. Returns a
`ZerohashFundSession`.

**Parameters:**

| Parameter | Type | Default | Description |
|---|---|---|---|
| `jwt` | `String` | — | JWT token authenticating the end user |
| `environment` | `Environment` | `.production` | `.sandbox` or `.production` |
| `theme` | `Theme` | `.system` | `.light`, `.dark`, or `.system` |
| `callbacks` | `FundCallbacks` | empty | Event callbacks for the Fund flow |

### ZerohashFundSession

#### `present(from:)`

Presents the Fund UI modally from the specified view controller.

- **Parameter** `viewController: UIViewController` — the view controller to present from

#### `cancel()`

Cancels the session if it is active.

#### `isActive`

A boolean indicating whether the session is currently active.

### Types

#### Environment

```swift
enum Environment {
    case sandbox     // Certification / testing environment
    case production  // Live environment
}
```

#### Theme

```swift
enum Theme {
    case light   // Force light theme
    case dark    // Force dark theme
    case system  // Follow the device appearance setting
}
```

#### FundCallbacks

```swift
struct FundCallbacks {
    var onClose: (() -> Void)?
    var onError: ((ErrorEvent) -> Void)?
    var onEvent: ((GenericEvent) -> Void)?
    var onFund: ((FundEvent) -> Void)?
}
```

## Callbacks and Events

### onFund

Called when a fund event occurs during the Fund flow.

```swift
fund.success      // Bool    — true when the deposit was processed
fund.status       // String? — current deposit status
fund.data         // [String: Any] — raw event payload
fund.jsonString   // String  — raw JSON string
```

### onError

Called when an error occurs during the flow.

```swift
error.code        // String — error code
error.message     // String — human-readable error message
error.data        // [String: Any] — additional error details
error.jsonString  // String — raw JSON string
error.timestamp   // Date   — when the error occurred
```

### onEvent

Called for generic analytic and lifecycle events during the flow.

```swift
event.type                // String        — event type identifier
event.data                // [String: Any] — event payload
event.getString("key")    // String?
event.getInt("key")       // Int?
event.getBool("key")      // Bool?
event.getDouble("key")    // Double?
event.getObject("key")    // [String: Any]?
```

### onClose

Called when the session is closed by the user or programmatically via
`cancel()`.

## Themes and Customization

### Setting Theme

The SDK supports three theme options:

```swift
// Light theme
ZerohashSDK.configureFund(jwt: token, theme: .light)

// Dark theme
ZerohashSDK.configureFund(jwt: token, theme: .dark)

// System theme (default) — matches device settings
ZerohashSDK.configureFund(jwt: token, theme: .system)
```

### Theme Behavior

- **`.system`** — Automatically switches between light and dark based on device settings
- **`.light`** — Forces light theme regardless of device settings
- **`.dark`** — Forces dark theme regardless of device settings

The theme applies to the WebView content and the loading indicator.

## Contact

For additional support or questions about the zerohash platform:
- [Technical Support](https://zerohash.com/)
- [Documentation](https://docs.zerohash.com)
