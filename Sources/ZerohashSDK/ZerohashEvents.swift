import Foundation

// MARK: - Callbacks

public struct ZerohashCallbacks {
    public var onClose: (() -> Void)?
    public var onDeposit: ((DepositEvent) -> Void)?
    public var onError: ((ErrorEvent) -> Void)?
    public var onEvent: ((GenericEvent) -> Void)?

    public init(
        onClose: (() -> Void)? = nil,
        onDeposit: ((DepositEvent) -> Void)? = nil,
        onError: ((ErrorEvent) -> Void)? = nil,
        onEvent: ((GenericEvent) -> Void)? = nil
    ) {
        self.onClose = onClose
        self.onDeposit = onDeposit
        self.onError = onError
        self.onEvent = onEvent
    }
}

// MARK: - Events

public struct DepositEvent {
    public let depositId: String?
    public let status: String?
    public let success: Bool
    public let assetId: String?
    public let networkId: String?
    public let amount: String?
    public let data: [String: Any]
    public let jsonString: String

    public init(from data: [String: Any], jsonString: String = "") {
        self.data = data
        self.jsonString = jsonString
        self.depositId = data["depositId"] as? String
        self.status = data["status"] as? String
        self.success = data["success"] as? Bool ?? false
        self.assetId = data["assetId"] as? String
        self.networkId = data["networkId"] as? String
        self.amount = data["amount"] as? String
    }
}

public struct ErrorEvent {
    public let code: String
    public let message: String
    public let data: [String: Any]
    public let jsonString: String
    public let timestamp: Date

    public init(from data: [String: Any], jsonString: String = "") {
        self.data = data
        self.jsonString = jsonString
        self.timestamp = Date()
        self.code = data["code"] as? String ?? "UNKNOWN_ERROR"
        self.message = data["message"] as? String ?? "An unknown error occurred"
    }
}

public struct GenericEvent {
    public let type: String
    public let data: [String: Any]
    public let jsonString: String

    public init(type: String, data: [String: Any], jsonString: String = "") {
        self.type = type
        self.data = data
        self.jsonString = jsonString
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
