import Foundation

// MARK: - CryptoWithdrawalsCallbacks

public struct CryptoWithdrawalsCallbacks {
    public var onClose: (() -> Void)?
    public var onWithdrawal: ((CryptoWithdrawalsEvent) -> Void)?
    public var onError: ((ErrorEvent) -> Void)?
    public var onEvent: ((GenericEvent) -> Void)?

    public init(
        onClose: (() -> Void)? = nil,
        onWithdrawal: ((CryptoWithdrawalsEvent) -> Void)? = nil,
        onError: ((ErrorEvent) -> Void)? = nil,
        onEvent: ((GenericEvent) -> Void)? = nil
    ) {
        self.onClose = onClose
        self.onWithdrawal = onWithdrawal
        self.onError = onError
        self.onEvent = onEvent
    }
}

// MARK: - CryptoWithdrawalsEvent

/// Completion payload for the crypto-withdrawals flow.
///
/// Field shape mirrors `CryptoWithdrawalsCompletedData` from `@zerohash/callbacks`:
/// the web SDK emits a flat object (no `.data` wrapper) that the mobile web app
/// forwards over the bridge as a `crypto-withdrawal` message.
public struct CryptoWithdrawalsEvent {
    /// The withdrawal request ID returned from the API.
    public let withdrawalRequestId: String?
    public let data: [String: Any]
    public let jsonString: String

    public init(
        withdrawalRequestId: String?,
        data: [String: Any] = [:],
        jsonString: String = ""
    ) {
        self.withdrawalRequestId = withdrawalRequestId
        self.data = data
        self.jsonString = jsonString
    }

    public func getString(_ key: String) -> String? {
        return data[key] as? String
    }
}
