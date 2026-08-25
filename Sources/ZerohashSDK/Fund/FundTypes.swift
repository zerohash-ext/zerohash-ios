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

/// Status of a deposit funded from an external source, delivered to
/// `FundCallbacks.onDeposit`.
///
/// A different shape from `FundEvent`: this path reports a *status*, so it carries
/// the status value, its human-readable detail, and the account-matching
/// validation. `status` arrives as an object (`{ value, details, occurredAt }`) and
/// there is no flat success field, so both are derived from `status.value` —
/// matching how connect-ios and connect-android parse the same payload.
public struct FundDepositEvent {
    /// Unique identifier for the deposit.
    public let depositId: String?
    /// Status value, e.g. `PROCESSED`, `FAILED`, `PENDING`.
    public let status: String?
    /// Human-readable detail for the status.
    public let statusDetails: String?
    /// When the status occurred (ISO 8601).
    public let statusOccurredAt: String?
    /// True once the deposit is processed. False while pending, verifying or failed.
    public let success: Bool
    /// Asset identifier (e.g. `BTC`, `USDC`).
    public let assetId: String?
    /// Network identifier (e.g. `bitcoin`, `ethereum`).
    public let networkId: String?
    /// Amount deposited.
    public let amount: String?
    /// Account-matching validation status, e.g. `PENDING`, `VALID`, `INVALID`, `ERROR`.
    public let accountMatchingStatus: String?
    /// Why account matching failed. On a name mismatch this is the only explanation
    /// available anywhere in the stack, so prefer it over reporting a bare id.
    public let accountMatchingReason: String?
    /// Untouched bridge payload, for anything not surfaced above.
    public let data: [String: Any]
    public let jsonString: String

    public init(from data: [String: Any], jsonString: String = "") {
        self.data = data
        self.jsonString = jsonString
        self.depositId = data["depositId"] as? String
        let status = data["status"] as? [String: Any]
        let statusValue = status?["value"] as? String
        self.status = statusValue
        self.statusDetails = status?["details"] as? String
        self.statusOccurredAt = status?["occurredAt"] as? String
        self.success = statusValue?.lowercased() == "processed"
        self.assetId = data["assetId"] as? String
        self.networkId = data["networkId"] as? String
        self.amount = data["amount"] as? String
        let validation = data["accountMatchingValidation"] as? [String: Any]
        self.accountMatchingStatus = validation?["status"] as? String
        self.accountMatchingReason = validation?["reason"] as? String
    }
}

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
