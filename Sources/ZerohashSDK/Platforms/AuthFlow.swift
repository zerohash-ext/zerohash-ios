import Foundation

// MARK: - Result types (Codable so they round-trip into JSONValue cleanly)

public struct AuthProfile: Codable, Equatable, Sendable,
                           CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let userId: String
    public let firstName: String
    public let lastName: String

    public init(userId: String, firstName: String, lastName: String) {
        self.userId = userId
        self.firstName = firstName
        self.lastName = lastName
    }

    public var description: String {
        "AuthProfile(<redacted>)"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: [:])
    }
}

public struct AuthProfileFailure: Codable, Equatable, Sendable {
    static let indeterminate = "PROFILE_INDETERMINATE"
    static let incomplete = "PROFILE_INCOMPLETE"
    static let unknownReason = "invalid_response"
    static let reasons: Set<String> = [
        "http_error", "invalid_response", "graphql_error", "timeout", "missing_field",
    ]
    static let outcomes: Set<String> = reasons.union(["ok"])
    static let errorCodes: Set<String> = [indeterminate, incomplete]

    public let error: String
    public let reason: String

    static func forReason(_ reason: String?) -> AuthProfileFailure {
        let knownReason = Self.knownReason(reason)

        return AuthProfileFailure(error: Self.profileError(for: knownReason), reason: knownReason)
    }

    private static func knownReason(_ reason: String?) -> String {
        guard let reason, reasons.contains(reason) else {
            return unknownReason
        }

        return reason
    }

    private static func profileError(for reason: String) -> String {
        switch reason {
        case "missing_field":
            return incomplete
        default:
            return indeterminate
        }
    }
}

public struct AuthLoginResult: Codable, Equatable, Sendable {
    /// Definitive logged-in state, folded from an auth.status check on the
    /// success path. False for user-closed / timeout / passkey-only /
    /// account-not-found outcomes.
    public let loggedIn: Bool
    /// Discriminant for UI messaging:
    /// "success" | "user-closed" | "timeout" | "passkey-only" | "account-not-found".
    public let outcome: String
    /// The social provider that led to the outcome, when known — e.g. "apple"
    /// for an "account-not-found" social signup redirect. nil when not
    /// applicable/unknown. Optional and omitted from the wire when nil, so it's
    /// an additive, backward-compatible field for consumers that want to tailor
    /// the message (e.g. "No Apple account found — sign up first").
    public let provider: String?
    public let profile: AuthProfile?
    public let profileFailure: AuthProfileFailure?
    public init(
        loggedIn: Bool,
        outcome: String,
        provider: String? = nil,
        profile: AuthProfile? = nil,
        profileFailure: AuthProfileFailure? = nil
    ) {
        self.loggedIn = loggedIn
        self.outcome = outcome
        self.provider = provider
        self.profile = profile
        self.profileFailure = profileFailure
    }
}

public struct AuthStatusResult: Codable, Equatable, Sendable {
    public let loggedIn: Bool
    public let profile: AuthProfile?
    public let profileFailure: AuthProfileFailure?
    public init(loggedIn: Bool, profile: AuthProfile? = nil, profileFailure: AuthProfileFailure? = nil) {
        self.loggedIn = loggedIn
        self.profile = profile
        self.profileFailure = profileFailure
    }
}

// MARK: - Flow protocol

public protocol AuthFlow: PlatformIdentity {
    @MainActor func login(ctx: ExecutionContext) async throws -> AuthLoginResult
    @MainActor func status(ctx: ExecutionContext) async throws -> AuthStatusResult
}
