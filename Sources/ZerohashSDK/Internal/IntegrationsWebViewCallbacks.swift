import Foundation

/// Flow-agnostic callback sink for `IntegrationsWebViewController`.
///
/// The controller drives the shared mobile-web bridge (OAuth, ZeroAuth scraping,
/// navigation, theming) and knows nothing about which product is running inside
/// it. Each session adapts its own public callback type (`FundCallbacks`,
/// `CryptoWithdrawalsCallbacks`) into this, so the bridge stays single-copy.
///
/// `onCompleted` / `onFailed` carry the raw payload rather than a typed event,
/// because the terminal shape differs per flow — Fund posts a `deposit` message,
/// crypto withdrawals a `crypto-withdrawal` one — and only the session knows how
/// to type it. Both terminal outcomes arrive as separate messages from the web
/// layer (`deposit`/`crypto-withdrawal` vs `transaction-failed`), so there is no
/// success flag to inspect here.
///
/// `onDepositStatus` is Fund-only, so it defaults to `nil` and the
/// crypto-withdrawals session simply leaves it unset.
struct IntegrationsWebViewCallbacks {
    var onClose: (() -> Void)?
    var onCompleted: (([String: Any], String) -> Void)?
    var onFailed: (([String: Any], String) -> Void)?
    var onDepositStatus: (([String: Any], String) -> Void)?
    var onError: ((ErrorEvent) -> Void)?
    var onLoaded: (() -> Void)?
    var onEvent: ((GenericEvent) -> Void)?

    init(
        onClose: (() -> Void)? = nil,
        onCompleted: (([String: Any], String) -> Void)? = nil,
        onFailed: (([String: Any], String) -> Void)? = nil,
        onDepositStatus: (([String: Any], String) -> Void)? = nil,
        onError: ((ErrorEvent) -> Void)? = nil,
        onLoaded: (() -> Void)? = nil,
        onEvent: ((GenericEvent) -> Void)? = nil
    ) {
        self.onClose = onClose
        self.onCompleted = onCompleted
        self.onFailed = onFailed
        self.onDepositStatus = onDepositStatus
        self.onError = onError
        self.onLoaded = onLoaded
        self.onEvent = onEvent
    }
}
