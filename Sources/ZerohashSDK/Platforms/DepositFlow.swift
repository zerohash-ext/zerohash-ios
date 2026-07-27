import Foundation

// MARK: - Currency-aware amount (mirrors @zeroauth/client contract.ts:88-100)

public enum AmountCurrency: String, Codable, Equatable, Sendable {
    case fiat
    case asset
}

public struct AmountSpec: Codable, Equatable, Sendable {
    public let value: String
    public let currency: AmountCurrency
    public init(value: String, currency: AmountCurrency) {
        self.value = value
        self.currency = currency
    }
}

public struct AmountSubmitted: Codable, Equatable, Sendable {
    public let value: String
    public let requestedCurrency: AmountCurrency
    /// Ticker associated with the submitted amount. Currently mirrors the
    /// requested asset (the automation does not yet scrape the symbol Coinbase
    /// renders), e.g. "USDC", "BTC".
    public let resolvedSymbol: String
    public init(value: String, requestedCurrency: AmountCurrency, resolvedSymbol: String) {
        self.value = value
        self.requestedCurrency = requestedCurrency
        self.resolvedSymbol = resolvedSymbol
    }
}

// MARK: - Request payload (mirrors GetDepositAddressPayload, contract.ts:128-136)

public struct GetDepositAddressPayload: Codable, Equatable, Sendable {
    public let asset: String
    public let network: String?
    public let amount: AmountSpec?
    public init(asset: String, network: String? = nil, amount: AmountSpec? = nil) {
        self.asset = asset
        self.network = network
        self.amount = amount
    }
}

// MARK: - Result (mirrors DepositAddressResult, contract.ts:115-126)

public struct DepositAddressResult: Codable, Equatable, Sendable {
    public let address: String
    public let destinationTag: String
    public let network: String
    public let asset: String
    public let warnings: [String]
    public let depositUri: String
    /// Present only for Lightning invoice flows. Encoder omits when nil.
    public let amountSubmitted: AmountSubmitted?
    public init(
        address: String,
        destinationTag: String,
        network: String,
        asset: String,
        warnings: [String],
        depositUri: String,
        amountSubmitted: AmountSubmitted? = nil
    ) {
        self.address = address
        self.destinationTag = destinationTag
        self.network = network
        self.asset = asset
        self.warnings = warnings
        self.depositUri = depositUri
        self.amountSubmitted = amountSubmitted
    }
}

// MARK: - Flow protocol

public protocol DepositFlow: PlatformIdentity {
    @MainActor func getDepositAddress(
        ctx: ExecutionContext,
        payload: GetDepositAddressPayload,
        overlay: OverlayOptions,
        // Contract-intended (contract.ts:38-41): when false, the branded
        // loading overlay is suppressed so the user can watch the automation
        // play out on the underlying page. Maps from the wire `initialOverlay`.
        showOverlay: Bool
    ) async throws -> DepositAddressResult
}

// MARK: - Decoding from the bridge wire payload

extension GetDepositAddressPayload {
    enum DecodeError: Error, Equatable {
        case missingPayload
    }

    /// Decodes a `GetDepositAddressPayload` from the bridge's `JSONValue`
    /// request payload. `JSONValue` is itself `Codable`, so we round-trip
    /// through `Data` to reuse the synthesized `Codable` conformance.
    ///
    /// Note: declared at the default (internal) access level because the
    /// `JSONValue` parameter type is internal to the SDK; a `public` method
    /// cannot expose an internal type. The bridge router that calls this is
    /// also internal, so internal access is sufficient.
    static func decode(from payload: JSONValue?) throws -> GetDepositAddressPayload {
        guard let payload else { throw DecodeError.missingPayload }
        let data = try JSONEncoder().encode(payload)
        return try JSONDecoder().decode(GetDepositAddressPayload.self, from: data)
    }
}
