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

// MARK: - IntegrationsDepositEvent

/// Status of a deposit funded from a connected external account — the shared
/// "auth as a feature" integrations path. Delivered to `FundCallbacks.onDeposit`
/// and `CryptoDepositsCallbacks.onDeposit`.
///
/// One type serves both because the payload is built by the shared web hook
/// (`useHandleDepositStatus`), not by the host SDK, so it is byte-identical
/// whichever flow the session is running. It arrives on the `deposit-status`
/// bridge message in both cases.
///
/// A different shape from `FundEvent`: this path reports a *status*, so it carries
/// the status value, its human-readable detail, and the account-matching
/// validation. `status` arrives as an object (`{ value, details, occurredAt }`) and
/// there is no flat success field, so both are derived from `status.value` —
/// matching how connect-ios and connect-android parse the same payload.
public struct IntegrationsDepositEvent {
    /// Unique identifier for the deposit.
    public let depositId: String?
    /// Status value, e.g. `PROCESSED`, `FAILED`, `PENDING`.
    public let status: String?
    /// Human-readable detail for the status.
    public let statusDetails: String?
    /// When the status occurred (ISO 8601).
    public let statusOccurredAt: String?
    /// True once the deposit is processed **and** account matching is not holding
    /// it back. False while pending, verifying or failed.
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

    /// The one status the shared integrations flow treats as success. Unlike Auth
    /// on connect-ios — which also accepts `CONFIRMED`, gated on a profile flag
    /// that never reaches the bridge — `useHandleDepositStatus` in
    /// `integrations-flow` shows the success screen only at `PROCESSED`, so
    /// `CONFIRMED` is still in flight here.
    private static let successStatus = "processed"

    /// Account-matching states the web flow routes away from success before it
    /// ever looks at the status: `PENDING` shows the verifying screen, `INVALID`
    /// and `ERROR` show the failed screen. Absent, `VALID`, or any value we don't
    /// know yet falls through to the status check, exactly as the web hook does.
    private static let nonSuccessMatchingStatuses: Set<String> = ["pending", "invalid", "error"]

    public init(from data: [String: Any], jsonString: String = "") {
        self.data = data
        self.jsonString = jsonString
        self.depositId = data["depositId"] as? String
        let status = data["status"] as? [String: Any]
        let statusValue = status?["value"] as? String
        self.status = statusValue
        self.statusDetails = status?["details"] as? String
        self.statusOccurredAt = status?["occurredAt"] as? String
        self.assetId = data["assetId"] as? String
        self.networkId = data["networkId"] as? String
        self.amount = data["amount"] as? String
        let validation = data["accountMatchingValidation"] as? [String: Any]
        let matchingStatus = validation?["status"] as? String
        self.accountMatchingStatus = matchingStatus
        self.accountMatchingReason = validation?["reason"] as? String
        let matchingBlocks = matchingStatus
            .map { Self.nonSuccessMatchingStatuses.contains($0.lowercased()) } ?? false
        self.success = statusValue?.lowercased() == Self.successStatus && !matchingBlocks
    }
}
