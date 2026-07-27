import Foundation

// MARK: - Result model (mirrors AssetBalance, contract.ts:117-126)

public struct AssetBalance: Codable, Equatable, Sendable {
    /// Ticker: asset.displaySymbol ?? asset.platformName ?? "".
    public let key: String
    /// Human name, e.g. "Bitcoin".
    public let label: String
    /// Crypto quantity (string decimal).
    public let amount: String
    /// Fiat value (string decimal).
    public let notional: String
    /// Display fiat currency for the notional (crypto: e.g. "USD"; cash: account-wide or nil).
    public let currency: String?
    /// Crypto only: staking.summary.totalStakedPercent * 100 as a string; cash: nil.
    public let totalStakedPercent: String?
    /// Currently always nil in this code path.
    public let precision: Int?
    /// ISO-8601 timestamp captured when the balance was read.
    public let extractedAt: String

    public init(
        key: String,
        label: String,
        amount: String,
        notional: String,
        currency: String?,
        totalStakedPercent: String?,
        precision: Int?,
        extractedAt: String
    ) {
        self.key = key
        self.label = label
        self.amount = amount
        self.notional = notional
        self.currency = currency
        self.totalStakedPercent = totalStakedPercent
        self.precision = precision
        self.extractedAt = extractedAt
    }
}

// MARK: - Flow protocol

public protocol BalanceFlow: PlatformIdentity {
    /// Returns all asset balances (crypto + cash) for the authenticated session.
    /// Throws `PlatformError.underlying("not logged in")` when unauthenticated,
    /// `BALANCES_INDETERMINATE: <op> — ...` (retryable) on an incomplete load,
    /// and `CHALLENGE_UNSOLVED` (retryable) when a captcha is not solved in time.
    @MainActor func getBalance(
        ctx: ExecutionContext,
        overlay: OverlayOptions,
        showOverlay: Bool
    ) async throws -> [AssetBalance]
}
