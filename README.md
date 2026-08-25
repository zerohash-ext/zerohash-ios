# zerohash-ios

![Swift](https://img.shields.io/badge/Swift-6.0%2B-orange.svg)
![Platform](https://img.shields.io/badge/Platform-iOS%2017%2B-blue.svg)
![SPM Compatible](https://img.shields.io/badge/Swift%20Package%20Manager-compatible-brightgreen.svg)

Swift SDK for integrating [zerohash](https://docs.zerohash.com) products into your iOS app.

The SDK exposes three flows you can present from your app:

- **Fund** — account funding / pay-to-settle flow
- **Crypto Withdrawals** — withdraw crypto to an external address
- **Fund Withdrawals** — withdraw funds to a linked (Auth connection) destination

## Features

- Each flow exposed through a single SDK call
- WebView bridge for JS/native messaging over a hardened `WKWebView`
- Light, dark, and system theming
- Typed event callbacks
- Sandbox and production environments

## Requirements

- iOS 17+
- Swift 6.0+
- Xcode 16.0+

### Required Info.plist keys

Crypto transactions in the Fund SDK can be held by the exchange for an identity check, which the
user completes inside the SDK's WebView using the camera. Your app must declare
both keys below.

| Key | Why |
| --- | --- |
| `NSCameraUsageDescription` | Liveness / document capture during the identity check |
| `NSMicrophoneUsageDescription` | Requested alongside the camera by the identity check |

## Installation

### Swift Package Manager

#### Using Xcode

1. In Xcode, select **File > Add Package Dependencies...**
2. Enter the repository URL: `https://github.com/zerohash-ext/zerohash-ios`
3. Select the version rule you want to use (we recommend up to next major)
4. Click **Add Package**

#### Using Package.swift

Add ZerohashSDK as a dependency in your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/zerohash-ext/zerohash-ios", .upToNextMinor(from: "1.2.0"))
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

Before presenting a flow, you'll need to obtain a JWT token from your
backend. This token authenticates the end user with the zerohash platform
and carries the permissions for the flow you're presenting.

> For detailed instructions on obtaining JWT tokens, please refer to the [zerohash documentation](https://docs.zerohash.com).

## Usage

### Fund

The Fund app handles account funding and pay-to-settle. Use `onCompleted` and
`onFailed` to react to the deposit's terminal outcome.

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
            onLoaded: { print("Fund ready") },
            onEvent: { event in
                print("Fund event: \(event.type)")
            },
            onCompleted: { fund in
                print("Deposited \(fund.amount ?? "?") \(fund.assetSymbol ?? "?")")
                print("Transaction: \(fund.transactionId ?? "unknown")")
            },
            onFailed: { fund in
                print("Deposit failed: \(fund.transactionId ?? "unknown")")
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

### Crypto Withdrawals

The Crypto Withdrawals app walks the end user through withdrawing a crypto
asset to an external address. Use `onCompleted` and `onFailed` to react to the
withdrawal's terminal outcome.

```swift
import UIKit
import ZerohashSDK

class WithdrawalsViewController: UIViewController {

    private var withdrawalsSession: ZerohashCryptoWithdrawalsSession?

    @IBAction func startWithdrawalTapped(_ sender: UIButton) {
        let callbacks = CryptoWithdrawalsCallbacks(
            onClose: { print("Crypto Withdrawals closed") },
            onCompleted: { withdrawal in
                print("Withdrawal submitted: \(withdrawal.withdrawalRequestId ?? "unknown")")
            },
            onFailed: { withdrawal in
                print("Withdrawal failed: \(withdrawal.withdrawalRequestId ?? "unknown")")
            },
            onError: { error in
                print("Crypto Withdrawals error \(error.code): \(error.message)")
            },
            onLoaded: { print("Crypto Withdrawals ready") },
            onEvent: { event in
                print("Crypto Withdrawals event: \(event.type)")
            }
        )

        withdrawalsSession = ZerohashSDK.configureCryptoWithdrawals(
            jwt: "your-jwt-token",
            environment: .production,
            theme: .system,
            callbacks: callbacks
        )

        withdrawalsSession?.present(from: self)
    }
}
```

### Fund Withdrawals

The Fund Withdrawals app walks the end user through withdrawing funds to a
linked (Auth connection) destination. Use `onCompleted` to react to the
completed withdrawal.

```swift
import UIKit
import ZerohashSDK

class FundWithdrawalsViewController: UIViewController {

    private var fundWithdrawalsSession: ZerohashFundWithdrawalsSession?

    @IBAction func startFundWithdrawalTapped(_ sender: UIButton) {
        let callbacks = FundWithdrawalsCallbacks(
            onClose: { print("Fund Withdrawals closed") },
            onCompleted: { withdrawal in
                print("Withdrawal initiated: \(withdrawal.amount ?? "unknown") \(withdrawal.assetSymbol ?? "")")
            },
            onError: { error in
                print("Fund Withdrawals error \(error.code): \(error.message)")
            },
            onEvent: { event in
                print("Fund Withdrawals event: \(event.type)")
            }
        )

        fundWithdrawalsSession = ZerohashSDK.configureFundWithdrawals(
            jwt: "your-jwt-token",
            environment: .production,
            theme: .system,
            callbacks: callbacks
        )

        fundWithdrawalsSession?.present(from: self)
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

#### `configureCryptoWithdrawals(jwt:environment:theme:callbacks:)`

Configures a Crypto Withdrawals session that can be presented later. Returns a
`ZerohashCryptoWithdrawalsSession`.

**Parameters:**

| Parameter | Type | Default | Description |
|---|---|---|---|
| `jwt` | `String` | — | JWT token authenticating the end user |
| `environment` | `Environment` | `.production` | `.sandbox` or `.production` |
| `theme` | `Theme` | `.system` | `.light`, `.dark`, or `.system` |
| `callbacks` | `CryptoWithdrawalsCallbacks` | empty | Event callbacks for the Crypto Withdrawals flow |

#### `configureFundWithdrawals(jwt:environment:theme:callbacks:)`

Configures a Fund Withdrawals session that can be presented later. Returns a
`ZerohashFundWithdrawalsSession`.

**Parameters:**

| Parameter | Type | Default | Description |
|---|---|---|---|
| `jwt` | `String` | — | JWT token authenticating the end user |
| `environment` | `Environment` | `.production` | `.sandbox` or `.production` |
| `theme` | `Theme` | `.system` | `.light`, `.dark`, or `.system` |
| `callbacks` | `FundWithdrawalsCallbacks` | empty | Event callbacks for the Fund Withdrawals flow |

### ZerohashFundSession / ZerohashCryptoWithdrawalsSession / ZerohashFundWithdrawalsSession

All session types expose the same lifecycle:

#### `present(from:)`

Presents the flow's UI modally from the specified view controller.

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
    var onCompleted: ((FundEvent) -> Void)?
    var onFailed: ((FundEvent) -> Void)?
    var onDeposit: ((FundDepositEvent) -> Void)?
    var onError: ((ErrorEvent) -> Void)?
    var onLoaded: (() -> Void)?
    var onEvent: ((GenericEvent) -> Void)?
}
```

#### CryptoWithdrawalsCallbacks

```swift
struct CryptoWithdrawalsCallbacks {
    var onClose: (() -> Void)?
    var onCompleted: ((CryptoWithdrawalsEvent) -> Void)?
    var onFailed: ((CryptoWithdrawalsEvent) -> Void)?
    var onError: ((ErrorEvent) -> Void)?
    var onLoaded: (() -> Void)?
    var onEvent: ((GenericEvent) -> Void)?
}
```

#### FundWithdrawalsCallbacks

```swift
struct FundWithdrawalsCallbacks {
    var onClose: (() -> Void)?
    var onCompleted: ((FundWithdrawalsEvent) -> Void)?
    var onError: ((ErrorEvent) -> Void)?
    var onLoaded: (() -> Void)?
    var onEvent: ((GenericEvent) -> Void)?
}
```

> Callback names match the zerohash web SDK, so the same handler names apply
> whether you integrate on web, iOS or Android. The flow is identified by the
> session type, not the callback name.
>
> Fund Withdrawals has no `onFailed`: it cannot detect a failure once the
> withdrawal is submitted, so nothing in the stack reports one. A pre-submission
> problem arrives on `onError`.

## Callbacks and Events

### onCompleted / onFailed

The flow's terminal outcome. `onCompleted` fires when the transaction succeeded,
`onFailed` when it ended in a failed state. Both receive the same event type —
which callback fired tells you the outcome, so there is no status field to check.

A failed transaction is a flow outcome, **not** an error. Handle both if you need
to cover every unsuccessful path.

The two flows differ in one respect. A failed **deposit** (Fund) fires `onFailed`
only. A failed **crypto withdrawal** fires `onFailed` *and* `onError`, for
backwards compatibility with hosts written before `onFailed` existed — `onError`
was that flow's only failure signal. Build against `onFailed` in both cases; if
you handle both callbacks, guard against counting a failed withdrawal twice. The
compatibility `onError` is deprecated and will be removed in a future major
version.

Fund (`FundEvent`):

```swift
fund.depositAddress   // String? — deposit address for the asset
fund.network          // String? — network used for the deposit
fund.assetSymbol      // String? — asset symbol (e.g. "BTC.BITCOIN")
fund.amount           // String? — amount deposited
fund.transactionId    // String? — backend transaction id
fund.fundId           // String? — fund the deposit was credited to
fund.notionalAmount   // String? — notional (fiat) amount
fund.data             // [String: Any] — raw event payload
fund.jsonString       // String  — raw JSON string
fund.getString("key") // String?  (also getInt/getBool/getDouble/getObject)
```

### onDeposit (Fund only)

A deposit funded from an **external source** (the "connect an account" path) does
not reach `onCompleted`/`onFailed` at all. It reports on `onDeposit`, with a
`FundDepositEvent` — matching `onDeposit` on the Fund web SDK.

`onDeposit` is a **status, not an outcome**. It also fires while account matching is
verifying, and can arrive more than once for the same deposit, so do not treat the
call itself as completion:

```swift
deposit.depositId              // String? — unique identifier for the deposit
deposit.status                 // String? — "PROCESSED", "FAILED", "PENDING", ...
deposit.statusDetails          // String? — human-readable detail for the status
deposit.statusOccurredAt       // String? — when it occurred (ISO 8601)
deposit.success                // Bool    — true once processed; false while pending or failed
deposit.assetId                // String? — asset identifier (e.g. "USDC")
deposit.networkId              // String? — network identifier (e.g. "ethereum")
deposit.amount                 // String? — amount deposited
deposit.accountMatchingStatus  // String? — "PENDING", "VALID", "INVALID", "ERROR"
deposit.accountMatchingReason  // String? — why account matching failed
deposit.data                   // [String: Any] — raw event payload
deposit.jsonString             // String  — raw JSON string
```

On a name mismatch, `accountMatchingReason` is the only explanation available
anywhere in the stack, so prefer it over reporting a bare id.

A manual or Pay deposit is unaffected: it is terminal, and reaches
`onCompleted`/`onFailed` with all seven `FundEvent` fields as listed above.

Crypto Withdrawals (`CryptoWithdrawalsEvent`):

```swift
withdrawal.withdrawalRequestId  // String? — withdrawal request ID returned by the API
withdrawal.status               // String? — terminal status, e.g. "CONFIRMED" or "FAILED"
withdrawal.statusDetails        // String? — why; on a failure this is the only explanation available
withdrawal.assetId              // String? — asset identifier (e.g. "btc")
withdrawal.networkId            // String? — network identifier (e.g. "bitcoin")
withdrawal.amount               // String? — amount withdrawn
withdrawal.data                 // [String: Any] — raw event payload
withdrawal.jsonString           // String  — raw JSON string
withdrawal.getString("key")     // String?  (also getInt/getBool/getDouble/getObject)
```

Fund Withdrawals (`FundWithdrawalsEvent`), delivered to `onCompleted`. This flow
has no `onFailed`:

```swift
withdrawal.externalAccountId         // String? — resolved destination account
withdrawal.assetSymbol               // String? — asset withdrawn
withdrawal.amount                    // String? — amount withdrawn
withdrawal.data                      // [String: Any] — raw event payload
withdrawal.jsonString                // String  — raw JSON string
withdrawal.getString("key")          // String?
```

### onLoaded

Called once the flow's WebView content is ready — specifically when the web
component has mounted in the page. The same moment is also emitted through
`onEvent` as `APP_LOADED`.

Note this is **earlier** than the web SDK's `onLoaded`, which fires when the flow
itself has booted and rendered. The web layer's own ready signal is not currently
forwarded over the bridge, so do not treat this as "the user can see the flow" —
dismissing a loading spinner here can uncover a still-blank WebView.

### onError

Called when an SDK or request error occurs (network, auth, validation, config).
Terminal transaction failures arrive on `onFailed` instead.

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

Both flows support the same three theme options:

```swift
// Light theme
ZerohashSDK.configureFund(jwt: token, theme: .light)

// Dark theme
ZerohashSDK.configureCryptoWithdrawals(jwt: token, theme: .dark)

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
