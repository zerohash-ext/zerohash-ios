import Foundation

// MARK: - CryptoDepositsCallbacks

/// Host callbacks for the crypto-deposits flow.
///
/// Names match the zerohash web SDK's callback contract so a partner
/// integrating on web and native writes the same handlers. The flow is
/// identified by the session type, not by the callback name.
///
/// This flow runs the "auth as a feature" integrations path — the user can fund
/// from a connected external account. That path reports on `onDeposit`, and the
/// flow's own screens report on `onCompleted`/`onFailed`. Same split as Fund.
///
/// A terminal **failed** deposit arrives on `onFailed`, carrying the same fields
/// as a completion — not on `onError`, which stays for SDK/request errors
/// (network, auth, validation). Hosts show different UI for "the money movement
/// failed" than for "the SDK broke", so the two must not be conflated.
///
public struct CryptoDepositsCallbacks {
    public var onClose: (() -> Void)?
    /// The deposit completed.
    public var onCompleted: ((CryptoDepositsEvent) -> Void)?
    /// The deposit itself failed — a terminal outcome of the flow, not an SDK
    /// error. Carries the same fields as `onCompleted`.
    public var onFailed: ((CryptoDepositsEvent) -> Void)?
    /// In-flight status of a deposit funded from a connected external account.
    ///
    /// Non-terminal and repeatable: the web layer keeps polling after a deposit
    /// is terminal, so the same status can arrive more than once. Read the
    /// outcome off `status` / `success` rather than treating the call itself as
    /// one. Same payload the Fund flow delivers — both come from the shared
    /// integrations hook.
    public var onDeposit: ((IntegrationsDepositEvent) -> Void)?
    public var onError: ((ErrorEvent) -> Void)?
    /// The flow finished loading and is ready.
    public var onLoaded: (() -> Void)?
    public var onEvent: ((GenericEvent) -> Void)?

    public init(
        onClose: (() -> Void)? = nil,
        onCompleted: ((CryptoDepositsEvent) -> Void)? = nil,
        onFailed: ((CryptoDepositsEvent) -> Void)? = nil,
        onDeposit: ((IntegrationsDepositEvent) -> Void)? = nil,
        onError: ((ErrorEvent) -> Void)? = nil,
        onLoaded: (() -> Void)? = nil,
        onEvent: ((GenericEvent) -> Void)? = nil
    ) {
        self.onClose = onClose
        self.onCompleted = onCompleted
        self.onFailed = onFailed
        self.onDeposit = onDeposit
        self.onError = onError
        self.onLoaded = onLoaded
        self.onEvent = onEvent
    }
}

// MARK: - CryptoDepositsEvent

/// Completion payload for the crypto-deposits flow.
///
/// The web SDK emits a flat completion object that the mobile web app forwards
/// over the bridge as a `crypto-deposit` message. Its own message type rather
/// than `deposit`, which already means fund's completion on this SDK and carries
/// a different shape (`transactionId`/`fundId`). The typed fields mirror the
/// crypto-deposits success payload; the raw `data` is preserved for any
/// additional keys.
///
/// The fields are the same in both destination modes. Whether the deposit went
/// to a Zero Hash internal wallet or a platform-owned external address is
/// decided by the JWT's `deposit_details.to_address`, not reported here.
public struct CryptoDepositsEvent {
    /// The deposit ID returned from the API.
    public let depositId: String?
    /// Asset symbol (e.g. `USDC`).
    public let assetSymbol: String?
    /// Network identifier (e.g. `ethereum`).
    public let network: String?
    /// Amount deposited.
    public let amount: String?
    /// Untouched bridge payload, for anything not surfaced above.
    public let data: [String: Any]
    public let jsonString: String

    public init(from data: [String: Any], jsonString: String = "") {
        self.data = data
        self.jsonString = jsonString
        self.depositId = data["depositId"] as? String
        self.assetSymbol = data["assetSymbol"] as? String
        self.network = data["network"] as? String
        self.amount = data["amount"] as? String
    }

    public func getString(_ key: String) -> String? {
        return data[key] as? String
    }
}
