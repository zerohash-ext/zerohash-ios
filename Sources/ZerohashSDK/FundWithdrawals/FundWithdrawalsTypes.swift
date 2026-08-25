import Foundation

// MARK: - FundWithdrawalsCallbacks

/// Host callbacks for the fund-withdrawals flow.
///
/// Names match the zerohash web SDK's callback contract so a partner integrating
/// on web and native writes the same handlers. The flow is identified by the
/// session type, not by the callback name.
///
/// There is no `onFailed`. This flow cannot detect a failure once the withdrawal
/// is submitted, so no surface in the stack reports one; a pre-submission problem
/// arrives on `onError`.
public struct FundWithdrawalsCallbacks {
    public var onClose: (() -> Void)?
    /// The withdrawal was submitted successfully.
    public var onCompleted: ((FundWithdrawalsEvent) -> Void)?
    public var onError: ((ErrorEvent) -> Void)?
    /// The flow finished loading and is ready.
    public var onLoaded: (() -> Void)?
    public var onEvent: ((GenericEvent) -> Void)?

    public init(
        onClose: (() -> Void)? = nil,
        onCompleted: ((FundWithdrawalsEvent) -> Void)? = nil,
        onError: ((ErrorEvent) -> Void)? = nil,
        onLoaded: (() -> Void)? = nil,
        onEvent: ((GenericEvent) -> Void)? = nil
    ) {
        self.onClose = onClose
        self.onCompleted = onCompleted
        self.onError = onError
        self.onLoaded = onLoaded
        self.onEvent = onEvent
    }
}

// MARK: - FundWithdrawalsEvent

/// Completion payload for the fund-withdrawals flow.
///
/// The web SDK emits a flat completion object that the mobile web app forwards
/// over the bridge as a `fund-withdrawal` message. The typed fields mirror the
/// fund-withdrawals success payload (`externalAccountId`, `assetSymbol`,
/// `amount`); the raw `data` is preserved for any additional keys.
public struct FundWithdrawalsEvent {
    public let externalAccountId: String?
    public let assetSymbol: String?
    public let amount: String?
    public let data: [String: Any]
    public let jsonString: String

    public init(
        externalAccountId: String?,
        assetSymbol: String?,
        amount: String?,
        data: [String: Any] = [:],
        jsonString: String = ""
    ) {
        self.externalAccountId = externalAccountId
        self.assetSymbol = assetSymbol
        self.amount = amount
        self.data = data
        self.jsonString = jsonString
    }

    public func getString(_ key: String) -> String? {
        return data[key] as? String
    }
}
