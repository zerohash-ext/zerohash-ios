# Zerohash iOS - Code Standards

> Essential coding standards for the Zerohash project.

---

## Naming Conventions

### Classes, Structs, Enums, Protocols
Use **PascalCase**:

```swift
class FundWebViewMessageHandler { }
struct FundCallbacks { }
enum Environment { }
protocol FundWebViewMessageHandlerDelegate { }
```

### Variables, Functions, Parameters
Use **camelCase**:

```swift
let jwt: String
var isActive: Bool
func sendMessageToPage(type: String, data: [String: Any]) { }
```

### Protocol Naming
Delegates end with `Delegate`:

```swift
protocol WebViewMessageHandlerDelegate: AnyObject { }
```

### Protocol Method Naming

**Pattern 1:** `objectDidAction`

```swift
func messageHandlerDidReceivePageReady(_ handler: WebViewMessageHandler)
func messageHandlerDidReceiveClose(_ handler: WebViewMessageHandler)
```

**Pattern 2:** `object:didAction:parameters:`

```swift
func messageHandler(_ handler: WebViewMessageHandler, didReceiveError data: [String: Any], jsonString: String)
```

### Callback Properties
Use `on` prefix for closure properties:

```swift
public var onClose: (() -> Void)?
public var onError: ((ErrorEvent) -> Void)?
public var onEvent: ((GenericEvent) -> Void)?
```

---

## Access Control

### Use Explicit Access Modifiers
Always specify access level:

```swift
public class Zerohash { }          // Public API
internal class WebViewController { } // Internal to module
private let jwt: String              // Private to file/class
```

### Order
1. `public` - External API
2. `internal` - Within module (can be omitted but prefer explicit)
3. `weak var` - For delegates to avoid retain cycles
4. `private` - Within class/struct

**Example:**

```swift
class MyClass {
    // MARK: - Properties

    weak var delegate: MyDelegate?      // Always weak for delegates
    private weak var webView: WKWebView?
    private let jwt: String
    private let theme: String
}
```

---

## Documentation

### Public APIs Must Be Documented
Use `///` for documentation:

```swift
/// Configures a Fund session that can be presented later
/// Configure while fetching JWT, then present instantly for optimal UX
/// - Parameters:
///   - jwt: JWT token for authentication
///   - environment: Environment to use (defaults to production)
///   - theme: UI theme (defaults to system)
///   - callbacks: Optional callbacks for Fund events
/// - Returns: A ZerohashFundSession that can be presented when ready
public static func configureFund(
    jwt: String,
    environment: Environment = .production,
    theme: Theme = .system,
    callbacks: FundCallbacks = FundCallbacks()
) -> ZerohashFundSession {
```

---

## Types

### Enums for Constants

```swift
public enum Environment: String {
    case sandbox = "sandbox"
    case production = "production"
}

public enum Theme: String {
    case light
    case dark
    case system
}
```

---

## File Organization

### Directory Structure

```
Sources/ZerohashSDK/
├── ZerohashSDK.swift          # public entry point (configureFund, configureCryptoWithdrawals)
├── ZerohashSDKTypes.swift     # Environment, Theme
├── ZerohashEvents.swift       # ErrorEvent, GenericEvent (shared across flows)
├── Fund/
│   ├── FundTypes.swift        # FundCallbacks, FundEvent
│   └── ZerohashFundSession.swift
├── CryptoWithdrawals/
│   ├── CryptoWithdrawalsTypes.swift
│   └── ZerohashCryptoWithdrawalsSession.swift
├── Internal/                  # shared mobile-web bridge, one copy for all flows
│   ├── IntegrationsWebViewCallbacks.swift
│   ├── IntegrationsWebViewController.swift
│   ├── IntegrationsWebViewMessageHandler.swift
│   ├── Constants.swift
│   └── Log.swift
├── Automation/                # ZeroAuth scraping session + overlays
├── Bridge/                    # envelope decoding, execution context
├── Platforms/                 # per-platform scraping flows (Coinbase, …)
└── UI/
    ├── Components/
    ├── ViewControllers/
    └── Theme/
```

Each flow owns only its public callback/event types and a session class; the
WebView bridge lives once in `Internal/` and is flow-agnostic.

### File Naming
- **PascalCase:** `WebViewMessageHandler.swift`
- **Match main type:** File name = main class/struct name
- **Helpers end with "Helper":** `ThemeHelper.swift`
- **Managers end with "Manager":** `WebViewOAuthManager.swift`
- **Types end with "Types":** `AuthTypes.swift`

---

## Quick Reference

| Element | Convention | Example |
|---------|-----------|---------|
| Class/Struct | PascalCase | `WebViewMessageHandler` |
| Variable/Function | camelCase | `sendMessageToPage` |
| Protocol | PascalCase + Delegate | `WebViewMessageHandlerDelegate` |
| Enum | PascalCase | `Environment` |
| Enum case | camelCase | `.production` |
| Callback property | on + action | `onClose`, `onError` |
| Protocol method | objectDidAction | `messageHandlerDidReceiveClose` |
| File name | PascalCase.swift | `WebViewMessageHandler.swift` |
| Access control | Explicit | `public`, `internal`, `private` |
| Documentation | /// | `/// Description` |
