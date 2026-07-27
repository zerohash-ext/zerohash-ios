import Foundation

// MARK: - Withdraw contract types
//
// Swift types for the withdraw wire contract. The JSON these encode to / decode
// from is what the Connect web app sends and expects, so the shapes must match it
// exactly. `AmountSpec` / `AmountCurrency` are reused from `DepositFlow.swift`.
//
// This file is TYPES ONLY — no Coinbase conformance, no router wiring, no JS.

// MARK: - Inputs

/// Amount to withdraw: a structured value+currency, or the literal "max".
public enum WithdrawAmount: Codable, Equatable, Sendable {
    case max
    case spec(AmountSpec)

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            guard s == "max" else {
                throw DecodingError.dataCorruptedError(
                    in: c, debugDescription: "WithdrawAmount string must be \"max\", got \"\(s)\"")
            }
            self = .max
            return
        }
        self = .spec(try c.decode(AmountSpec.self))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .max:            try c.encode("max")
        case .spec(let spec): try c.encode(spec)
        }
    }
}

/// Where the withdrawal is going.
public enum RecipientType: String, Codable, Equatable, Sendable {
    case selfCustody = "self-custody"
    case exchange
}

/// Travel-rule (FATF) beneficiary info.
public struct WithdrawTravelRule: Codable, Equatable, Sendable {
    public let name: String
    /// ISO 3166-1 alpha-2 (e.g. "BR", "US").
    public let country: String
    public init(name: String, country: String) {
        self.name = name
        self.country = country
    }
}

/// Regulatory transfer details Coinbase requires on some corridors: the purpose
/// of the transfer and the sender's relationship to the recipient.
public struct WithdrawTransferDetails: Codable, Equatable, Sendable {
    public let purpose: String
    public let relationship: String
    public init(purpose: String, relationship: String) {
        self.purpose = purpose
        self.relationship = relationship
    }
}

/// `withdraw.start` payload.
public struct StartWithdrawPayload: Codable, Equatable, Sendable {
    public let asset: String
    /// Omit for single-network assets (BTC, XRP, ATOM); required for multi-network
    /// assets (USDC, USDT, ETH L2s).
    public let network: String?
    public let address: String
    public let amount: WithdrawAmount
    /// XRP Tag / Memo for XRP, ATOM, XLM, EOS.
    public let destinationTag: String?
    public let recipientType: RecipientType?
    public let travelRule: WithdrawTravelRule?
    public let transferDetails: WithdrawTransferDetails?

    public init(
        asset: String,
        network: String? = nil,
        address: String,
        amount: WithdrawAmount,
        destinationTag: String? = nil,
        recipientType: RecipientType? = nil,
        travelRule: WithdrawTravelRule? = nil,
        transferDetails: WithdrawTransferDetails? = nil
    ) {
        self.asset = asset
        self.network = network
        self.address = address
        self.amount = amount
        self.destinationTag = destinationTag
        self.recipientType = recipientType
        self.travelRule = travelRule
        self.transferDetails = transferDetails
    }
}

/// `withdraw.continue` payload:
/// `{ kind: "otp", code }` delivers a 6-digit code; `{ kind: "poll" }` is a
/// passkey/processing bump (the caller just wants to know if the page moved on).
public enum ContinueWithdrawPayload: Codable, Equatable, Sendable {
    case otp(code: String)
    case poll

    private enum CodingKeys: String, CodingKey { case kind, code }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "otp":  self = .otp(code: try c.decode(String.self, forKey: .code))
        case "poll": self = .poll
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: c, debugDescription: "unknown continue kind \"\(kind)\"")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .otp(let code):
            try c.encode("otp", forKey: .kind)
            try c.encode(code, forKey: .code)
        case .poll:
            try c.encode("poll", forKey: .kind)
        }
    }
}

// MARK: - Outputs

/// Preview details Coinbase rendered for the send. All fields nullable.
public struct WithdrawDetails: Codable, Equatable, Sendable {
    public let fiatAmount: String?
    public let cryptoAmount: String?
    public let recipient: String?
    public let network: String?
    public let timeEstimate: String?
    public let fee: String?

    public init(
        fiatAmount: String?,
        cryptoAmount: String?,
        recipient: String?,
        network: String?,
        timeEstimate: String?,
        fee: String?
    ) {
        self.fiatAmount = fiatAmount
        self.cryptoAmount = cryptoAmount
        self.recipient = recipient
        self.network = network
        self.timeEstimate = timeEstimate
        self.fee = fee
    }
}

/// A PRIOR transfer blocking a new send.
public struct PendingTransfer: Codable, Equatable, Sendable {
    public let amount: String?
    public let recipient: String?
    public let completeBefore: String?
    public init(amount: String?, recipient: String?, completeBefore: String?) {
        self.amount = amount
        self.recipient = recipient
        self.completeBefore = completeBefore
    }
}

/// The `submitted` terminal payload — the `result` object in the
/// `submitted` arm of `WithdrawState`.
public struct WithdrawSubmittedResult: Codable, Equatable, Sendable {
    public let status: String
    public let completeBefore: String?
    public let referenceId: String?
    public let sendUuid: String?
    public let details: WithdrawDetails
    public init(
        status: String,
        completeBefore: String?,
        referenceId: String?,
        sendUuid: String?,
        details: WithdrawDetails
    ) {
        self.status = status
        self.completeBefore = completeBefore
        self.referenceId = referenceId
        self.sendUuid = sendUuid
        self.details = details
    }
}

/// Rejected `reason` discriminants. Shared so the JS and Swift sides agree by
/// constant, not hand-copied string.
public enum WithdrawRejectReason {
    public static let pendingTransfer  = "pending_transfer"
    public static let otpRejected      = "otp_rejected"
    public static let transferCanceled = "transfer_canceled"
    /// The send requires a passkey (WebAuthn) we can't complete in the WebView and
    /// Coinbase offered no code-based alternative. Terminal — the host should tell
    /// the user to enable SMS/authenticator 2FA.
    public static let passkeyUnsupported = "passkey_unsupported"
}

/// State returned at every pause/terminal point of a withdraw session — a
/// discriminated union on `state` (+ `kind` for the awaiting variants).
///
/// Custom `Codable`: Swift's synthesized enum encoding would NOT produce the
/// flat `{ state, kind, ... }` discriminator shape the web app parses, so the
/// encoder/decoder are hand-written to match the wire exactly.
public enum WithdrawState: Codable, Equatable, Sendable {
    case awaitingInputOtp(details: WithdrawDetails)
    case awaitingUserActionPasskey(details: WithdrawDetails)
    case awaitingUserActionIdVerification(details: WithdrawDetails, completeBefore: String?)
    case processing(details: WithdrawDetails)
    case submitted(result: WithdrawSubmittedResult)
    case rejected(reason: String, pendingTransfer: PendingTransfer?)

    private enum CodingKeys: String, CodingKey {
        case state, kind, details, completeBefore, result, reason, pendingTransfer
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .awaitingInputOtp(let details):
            try c.encode("awaiting-input", forKey: .state)
            try c.encode("otp", forKey: .kind)
            try c.encode(details, forKey: .details)

        case .awaitingUserActionPasskey(let details):
            try c.encode("awaiting-user-action", forKey: .state)
            try c.encode("passkey", forKey: .kind)
            try c.encode(details, forKey: .details)

        case .awaitingUserActionIdVerification(let details, let completeBefore):
            try c.encode("awaiting-user-action", forKey: .state)
            try c.encode("id-verification", forKey: .kind)
            try c.encode(details, forKey: .details)
            // contract: completeBefore is `string | null` (key always present).
            if let completeBefore {
                try c.encode(completeBefore, forKey: .completeBefore)
            } else {
                try c.encodeNil(forKey: .completeBefore)
            }

        case .processing(let details):
            try c.encode("processing", forKey: .state)
            try c.encode(details, forKey: .details)

        case .submitted(let result):
            try c.encode("submitted", forKey: .state)
            try c.encode(result, forKey: .result)

        case .rejected(let reason, let pendingTransfer):
            try c.encode("rejected", forKey: .state)
            try c.encode(reason, forKey: .reason)
            // `pendingTransfer?` is an optional key — omit when absent.
            try c.encodeIfPresent(pendingTransfer, forKey: .pendingTransfer)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let state = try c.decode(String.self, forKey: .state)
        switch state {
        case "awaiting-input":
            self = .awaitingInputOtp(details: try c.decode(WithdrawDetails.self, forKey: .details))

        case "awaiting-user-action":
            let kind = try c.decode(String.self, forKey: .kind)
            let details = try c.decode(WithdrawDetails.self, forKey: .details)
            switch kind {
            case "passkey":
                self = .awaitingUserActionPasskey(details: details)
            case "id-verification":
                self = .awaitingUserActionIdVerification(
                    details: details,
                    completeBefore: try c.decodeIfPresent(String.self, forKey: .completeBefore))
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .kind, in: c, debugDescription: "unknown awaiting-user-action kind \"\(kind)\"")
            }

        case "processing":
            self = .processing(details: try c.decode(WithdrawDetails.self, forKey: .details))

        case "submitted":
            self = .submitted(result: try c.decode(WithdrawSubmittedResult.self, forKey: .result))

        case "rejected":
            self = .rejected(
                reason: try c.decode(String.self, forKey: .reason),
                pendingTransfer: try c.decodeIfPresent(PendingTransfer.self, forKey: .pendingTransfer))

        default:
            throw DecodingError.dataCorruptedError(
                forKey: .state, in: c, debugDescription: "unknown withdraw state \"\(state)\"")
        }
    }
}

public extension WithdrawState {
    /// True when the session is over — the caller should dismiss the modal and
    /// clear its slot. `.submitted` always ends it; `.rejected` ends it EXCEPT
    /// `otp_rejected`, which is retriable on the SAME session; `.awaiting*` /
    /// `.processing` are pauses, not endings.
    var endsSession: Bool {
        switch self {
        case .submitted:
            return true
        case .rejected(let reason, _):
            return reason != WithdrawRejectReason.otpRejected
        case .awaitingInputOtp, .awaitingUserActionPasskey,
             .awaitingUserActionIdVerification, .processing:
            return false
        }
    }

    /// True when this (non-terminal) pause is completed by the user IN Coinbase's
    /// own UI — so the modal should be revealed rather than stepped aside for the
    /// host. Currently only ID-verification: passkey is NOT supported (the JS
    /// rejects with `passkey_unsupported` instead of producing the passkey state),
    /// so `awaitingUserActionPasskey` is unreachable and intentionally omitted here.
    var surfacesCoinbase: Bool {
        switch self {
        case .awaitingUserActionIdVerification:
            return true
        default:
            return false
        }
    }
}

// MARK: - Bridge payload decoding

extension StartWithdrawPayload {
    enum DecodeError: Error, Equatable { case missingPayload }

    /// Decode from the bridge's `JSONValue` request payload (round-trips through
    /// `Data` to reuse the synthesized `Codable`). Mirrors
    /// `GetDepositAddressPayload.decode`.
    static func decode(from payload: JSONValue?) throws -> StartWithdrawPayload {
        guard let payload else { throw DecodeError.missingPayload }
        let data = try JSONEncoder().encode(payload)
        return try JSONDecoder().decode(StartWithdrawPayload.self, from: data)
    }
}

extension ContinueWithdrawPayload {
    enum DecodeError: Error, Equatable { case missingPayload }

    static func decode(from payload: JSONValue?) throws -> ContinueWithdrawPayload {
        guard let payload else { throw DecodeError.missingPayload }
        let data = try JSONEncoder().encode(payload)
        return try JSONDecoder().decode(ContinueWithdrawPayload.self, from: data)
    }
}

// MARK: - Flow protocol
//
// NOTE: signatures are PROVISIONAL — how the live session handle is threaded
// across start/continue/cancel is finalized in Phase 3 once the session
// registry exists. Kept here so the contract is visible alongside the types.

/// Bundles the live session created by `startWithdraw` with the first state, so
/// the coordinator can store the handle (keyed by sessionId) and return the state.
///
/// The session is an `AutomationSessionHandle` — the long-lived, automation-driven
/// WebView this branch exposes for multi-step flows. It stays alive (drivable via
/// `evaluateAsync`, closable via `dismiss`, hide/reveal + step-aside for 2FA)
/// across the multiple bridge calls a withdraw session needs.
public struct WithdrawStartResult {
    public let session: AutomationSessionHandle
    public let state: WithdrawState
    public init(session: AutomationSessionHandle, state: WithdrawState) {
        self.session = session
        self.state = state
    }
}

public protocol WithdrawFlow: PlatformIdentity {
    @MainActor func startWithdraw(
        ctx: ExecutionContext,
        payload: StartWithdrawPayload,
        overlay: OverlayOptions,
        showOverlay: Bool
    ) async throws -> WithdrawStartResult

    @MainActor func continueWithdraw(
        session: AutomationSessionHandle,
        payload: ContinueWithdrawPayload
    ) async throws -> WithdrawState

    /// Returns whether Coinbase's "Cancel transfer" was found and clicked.
    @MainActor func cancelWithdraw(session: AutomationSessionHandle) async throws -> Bool
}
