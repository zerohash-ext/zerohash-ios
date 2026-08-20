import Foundation

// MARK: - FundWithdrawalsCallbacks

public struct FundWithdrawalsCallbacks {
    public var onClose: (() -> Void)?
    public var onWithdrawal: ((FundWithdrawalsEvent) -> Void)?
    public var onError: ((ErrorEvent) -> Void)?
    public var onEvent: ((GenericEvent) -> Void)?

    public init(
        onClose: (() -> Void)? = nil,
        onWithdrawal: ((FundWithdrawalsEvent) -> Void)? = nil,
        onError: ((ErrorEvent) -> Void)? = nil,
        onEvent: ((GenericEvent) -> Void)? = nil
    ) {
        self.onClose = onClose
        self.onWithdrawal = onWithdrawal
        self.onError = onError
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
