import Foundation

// MARK: - Shared Events

/// An SDK or request error: network, auth, validation, config. Distinct from a
/// flow's own terminal failure, which arrives on `onFailed` with the
/// transaction's details instead.
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

/// Catch-all for the flow's lifecycle/analytics events. `type` carries the
/// original event identifier and `data` its payload.
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
