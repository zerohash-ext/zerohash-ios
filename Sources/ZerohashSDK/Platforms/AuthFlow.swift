import Foundation

// MARK: - Result types (Codable so they round-trip into JSONValue cleanly)

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
    public init(loggedIn: Bool, outcome: String, provider: String? = nil) {
        self.loggedIn = loggedIn
        self.outcome = outcome
        self.provider = provider
    }
}

public struct AuthStatusResult: Codable, Equatable, Sendable {
    public let loggedIn: Bool
    public init(loggedIn: Bool) { self.loggedIn = loggedIn }
}

// MARK: - Flow protocol

public protocol AuthFlow: PlatformIdentity {
    @MainActor func login(ctx: ExecutionContext) async throws -> AuthLoginResult
    @MainActor func status(ctx: ExecutionContext) async throws -> AuthStatusResult
}
