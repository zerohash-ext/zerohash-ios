import Foundation

// MARK: - FundCallbacks

public struct FundCallbacks {
    public var onClose: (() -> Void)?
    public var onFund: ((FundEvent) -> Void)?
    public var onError: ((ErrorEvent) -> Void)?
    public var onEvent: ((GenericEvent) -> Void)?

    public init(
        onClose: (() -> Void)? = nil,
        onFund: ((FundEvent) -> Void)? = nil,
        onError: ((ErrorEvent) -> Void)? = nil,
        onEvent: ((GenericEvent) -> Void)? = nil
    ) {
        self.onClose = onClose
        self.onFund = onFund
        self.onError = onError
        self.onEvent = onEvent
    }
}

// MARK: - FundEvent

public struct FundEvent {
    public let success: Bool
    public let status: String?
    public let data: [String: Any]
    public let jsonString: String

    public init(success: Bool, status: String?, data: [String: Any] = [:], jsonString: String = "") {
        self.success = success
        self.status = status
        self.data = data
        self.jsonString = jsonString
    }

    public func getString(_ key: String) -> String? {
        return data[key] as? String
    }
}
