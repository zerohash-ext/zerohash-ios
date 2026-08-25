import Foundation

// MARK: - CryptoWithdrawalsCallbacks

/// Host callbacks for the crypto-withdrawals flow.
///
/// Names match the zerohash web SDK's callback contract so a partner
/// integrating on web and native writes the same handlers. The flow is
/// identified by the session type, not by the callback name.
public struct CryptoWithdrawalsCallbacks {
    public var onClose: (() -> Void)?
    /// The withdrawal was submitted successfully.
    public var onCompleted: ((CryptoWithdrawalsEvent) -> Void)?
    /// The withdrawal reached a terminal **failed** state. This is a flow
    /// outcome rather than an SDK error, and it carries the withdrawal's details.
    ///
    /// Note that a failed withdrawal currently fires `onError` **as well**, for
    /// backwards compatibility with hosts written before `onFailed` existed
    /// (`onError` used to be this flow's only failure signal). Build against
    /// `onFailed`; if you handle both, guard against counting one failure twice.
    /// The compatibility `onError` is deprecated and will be removed in a future
    /// major version. Fund does not do this — only crypto withdrawals.
    public var onFailed: ((CryptoWithdrawalsEvent) -> Void)?
    public var onError: ((ErrorEvent) -> Void)?
    /// The flow finished loading and is ready.
    public var onLoaded: (() -> Void)?
    public var onEvent: ((GenericEvent) -> Void)?

    public init(
        onClose: (() -> Void)? = nil,
        onCompleted: ((CryptoWithdrawalsEvent) -> Void)? = nil,
        onFailed: ((CryptoWithdrawalsEvent) -> Void)? = nil,
        onError: ((ErrorEvent) -> Void)? = nil,
        onLoaded: (() -> Void)? = nil,
        onEvent: ((GenericEvent) -> Void)? = nil
    ) {
        self.onClose = onClose
        self.onCompleted = onCompleted
        self.onFailed = onFailed
        self.onError = onError
        self.onLoaded = onLoaded
        self.onEvent = onEvent
    }
}

// MARK: - CryptoWithdrawalsEvent

/// Terminal payload for the crypto-withdrawals flow, delivered to
/// `onCompleted` or `onFailed`.
///
/// Field shape mirrors the web SDK's completed-withdrawal payload: a flat
/// object (no `.data` wrapper) forwarded over the bridge. Which callback fired tells
/// you the outcome — there is no status field.
public struct CryptoWithdrawalsEvent {
    /// The withdrawal request ID returned from the API.
    public let withdrawalRequestId: String?
    /// Terminal status value, e.g. `CONFIRMED` or `FAILED`.
    public let status: String?
    /// Human-readable reason for the status. On a failure this is the only
    /// explanation available anywhere in the stack, so prefer it over reporting a
    /// bare id.
    public let statusDetails: String?
    /// Asset identifier (e.g. `btc`, `eth`).
    public let assetId: String?
    /// Network identifier (e.g. `bitcoin`, `ethereum`).
    public let networkId: String?
    /// Amount withdrawn.
    public let amount: String?
    /// Untouched bridge payload, for anything not surfaced above.
    public let data: [String: Any]
    public let jsonString: String

    public init(from data: [String: Any], jsonString: String = "") {
        self.data = data
        self.jsonString = jsonString
        self.withdrawalRequestId = data["withdrawalRequestId"] as? String
        self.status = data["status"] as? String
        self.statusDetails = data["statusDetails"] as? String
        self.assetId = data["assetId"] as? String
        self.networkId = data["networkId"] as? String
        self.amount = data["amount"] as? String
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
