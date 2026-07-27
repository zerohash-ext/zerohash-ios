import Foundation

/// A generic auto-close rule for a modal WebView. While the modal is open the
/// supplied JavaScript is evaluated on an interval; the modal force-closes with
/// `ModalCloseReason.conditionMet(code)` once the script returns the SAME
/// non-empty condition-code string for `requiredHits` consecutive reads.
///
/// Platform-agnostic by design: the caller supplies the probe script — which
/// names its own condition(s) via the returned code — and decides what each
/// `.conditionMet(code)` close means (e.g. Coinbase maps "passkey-only" and
/// "account-not-found" to `auth.login` outcomes). The interval doubles as the
/// confirm gap between reads, so a transient/half-rendered DOM state can't
/// trigger a close.
public struct ModalAutoClose: Sendable {
    /// JS evaluated against the live page; evaluates to a non-empty condition-code
    /// string when matched, or a falsy/empty value (or throws) when not.
    public let probeJS: String
    /// Delay between successive reads (and the confirm gap between hits).
    public let intervalMs: Int
    /// Consecutive positive reads required before closing.
    public let requiredHits: Int

    public init(probeJS: String, intervalMs: Int = 250, requiredHits: Int = 2) {
        self.probeJS = probeJS
        self.intervalMs = intervalMs
        self.requiredHits = requiredHits
    }
}
