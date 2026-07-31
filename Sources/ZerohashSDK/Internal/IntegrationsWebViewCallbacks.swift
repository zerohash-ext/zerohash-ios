import Foundation

/// Flow-agnostic callback sink for `IntegrationsWebViewController`.
///
/// The controller drives the shared mobile-web bridge (OAuth, ZeroAuth scraping,
/// navigation, theming) and knows nothing about which product is running inside
/// it. Each session adapts its own public callback type (`FundCallbacks`,
/// `CryptoWithdrawalsCallbacks`) into this, so the bridge stays single-copy.
///
/// `onCompleted` carries the raw payload rather than a typed event, because the
/// completion shape differs per flow — Fund posts a `deposit` message, crypto
/// withdrawals a `withdrawal` one — and only the session knows how to type it.
struct IntegrationsWebViewCallbacks {
    var onClose: (() -> Void)?
    var onCompleted: (([String: Any], String) -> Void)?
    var onError: ((ErrorEvent) -> Void)?
    var onEvent: ((GenericEvent) -> Void)?

    init(
        onClose: (() -> Void)? = nil,
        onCompleted: (([String: Any], String) -> Void)? = nil,
        onError: ((ErrorEvent) -> Void)? = nil,
        onEvent: ((GenericEvent) -> Void)? = nil
    ) {
        self.onClose = onClose
        self.onCompleted = onCompleted
        self.onError = onError
        self.onEvent = onEvent
    }
}
