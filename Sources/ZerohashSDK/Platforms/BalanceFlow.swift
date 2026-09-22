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
    /// Percent of `amount` that cannot be withdrawn, as a decimal string with no
    /// "%" sign (e.g. "40"), or nil when nothing is locked.
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

    private enum CodingKeys: String, CodingKey {
        case key, label, amount, notional, currency, totalStakedPercent, precision, extractedAt
    }

    /// Written out by hand because the synthesized conformance uses
    /// `encodeIfPresent`, which drops a key whose value is nil. The contract
    /// types these as `T | null`, and a missing key is not the same as null to
    /// the consumer.
    ///
    /// Decoding stays synthesized: `decodeIfPresent` accepts both shapes, so
    /// rows written by an older build still round-trip.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(label, forKey: .label)
        try container.encode(amount, forKey: .amount)
        try container.encode(notional, forKey: .notional)
        try container.encode(currency, forKey: .currency)
        try container.encode(totalStakedPercent, forKey: .totalStakedPercent)
        try container.encode(precision, forKey: .precision)
        try container.encode(extractedAt, forKey: .extractedAt)
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
