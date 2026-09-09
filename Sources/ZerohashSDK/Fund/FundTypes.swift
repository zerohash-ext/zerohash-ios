import Foundation

// MARK: - FundCallbacks

/// Host callbacks for the Fund flow.
///
/// Names match the zerohash web SDK's callback contract so a partner
/// integrating on web and native writes the same handlers. The flow is
/// identified by the session type, not by the callback name — hence
/// `onCompleted` rather than `onFundCompleted`.
public struct FundCallbacks {
    public var onClose: (() -> Void)?
    /// The deposit completed successfully.
    public var onCompleted: ((FundEvent) -> Void)?
    /// The deposit reached a terminal **failed** state. This is a flow outcome,
    /// not an SDK error — `onError` is not called for it.
    public var onFailed: ((FundEvent) -> Void)?
    /// The status of a deposit funded from an external source (the "connect an
    /// account" flow). Mirrors `onDeposit` on the Fund web SDK.
    ///
    /// **Not terminal.** It also fires while account matching is verifying, and can
    /// arrive more than once for the same deposit — read the outcome off
    /// `FundDepositEvent.status` / `.success` rather than treating the call itself
    /// as completion. Deposits on this path report *only* here; `onCompleted` and
    /// `onFailed` cover the manual and Pay paths.
    public var onDeposit: ((FundDepositEvent) -> Void)?
    public var onError: ((ErrorEvent) -> Void)?
    /// The flow finished loading and is ready.
    public var onLoaded: (() -> Void)?
    public var onEvent: ((GenericEvent) -> Void)?

    public init(
        onClose: (() -> Void)? = nil,
        onCompleted: ((FundEvent) -> Void)? = nil,
        onFailed: ((FundEvent) -> Void)? = nil,
        onDeposit: ((FundDepositEvent) -> Void)? = nil,
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

// MARK: - FundDepositEvent

/// Deposit status for the Fund flow. The payload is built by the shared
/// integrations hook, so it is identical across every SDK that embeds that flow
/// — see `IntegrationsDepositEvent`, which crypto-deposits also delivers.
public typealias FundDepositEvent = IntegrationsDepositEvent

// MARK: - FundEvent

/// Terminal payload for the Fund flow, delivered to `onCompleted` or `onFailed`.
///
/// Field shape mirrors the web SDK's completed-deposit payload (and
/// `FundCompletedEvent` on Android): a flat object forwarded over the bridge.
/// There is no `success` flag — which callback fired tells you the outcome.
public struct FundEvent {
    /// Deposit address for the asset.
    public let depositAddress: String?
    /// Network used for the deposit.
    public let network: String?
    /// Asset symbol (e.g. `BTC.BITCOIN`).
    public let assetSymbol: String?
    /// Amount deposited.
    public let amount: String?
    /// Backend transaction id for the deposit.
    public let transactionId: String?
    /// Fund id the deposit was credited to.
    public let fundId: String?
    /// Notional (fiat) amount of the deposit.
    public let notionalAmount: String?
    /// Untouched bridge payload, for anything not surfaced above.
    public let data: [String: Any]
    public let jsonString: String

    public init(from data: [String: Any], jsonString: String = "") {
        self.data = data
        self.jsonString = jsonString
        self.depositAddress = data["depositAddress"] as? String
        self.network = data["network"] as? String
        self.assetSymbol = data["assetSymbol"] as? String
        self.amount = data["amount"] as? String
        self.transactionId = data["transactionId"] as? String
        self.fundId = data["fundId"] as? String
        self.notionalAmount = data["notionalAmount"] as? String
    }

    public func getString(_ key: String) -> String? {
        return data[key] as? String
    }

    public func getInt(_ key: String) -> Int? {
        return data[key] as? Int
    }

    public func getBool(_ key: String) -> Bool? {
        return data[key] as? Bool
    }

    public func getDouble(_ key: String) -> Double? {
        return data[key] as? Double
    }

    public func getObject(_ key: String) -> [String: Any]? {
        return data[key] as? [String: Any]
    }
}
