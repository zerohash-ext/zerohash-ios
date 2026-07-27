import Foundation

// MARK: - Wire roles

enum WireRole {
    static let host   = "zeroauth-host"
    static let native = "zeroauth-native"
}

// MARK: - Opaque JSON value

/// A minimal sum type for arbitrary JSON values that survive a round-trip
/// without losing structure. We deliberately do NOT decode `payload` to a
/// fixed Swift type here — each platform method decodes the payload it
/// expects. This keeps the dispatcher exchange-agnostic.
indirect enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.typeMismatch(JSONValue.self, .init(
            codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value"))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:           try c.encodeNil()
        case .bool(let v):    try c.encode(v)
        case .number(let v):  try c.encode(v)
        case .string(let v):  try c.encode(v)
        case .array(let v):   try c.encode(v)
        case .object(let v):  try c.encode(v)
        }
    }
}

// MARK: - Per-call options (wire DTOs)

/// The JSON-decoding layer for the inbound overlay customization, mirroring
/// the wire contract `OverlayOptions`
/// (scraper-browser-extensions/packages/client/src/contract.ts:22-27).
///
/// This is deliberately separate from `OverlayOptions.Partial`: this type's
/// only job is to faithfully decode the wire shape (every field optional).
/// Resolution against defaults stays in `OverlayOptions(resolving:)` — here
/// we just map optionals straight through via `asPartial`.
struct WireOverlayOptions: Codable, Equatable {
    let titles: [String]?
    let subtitles: [String]?
    let cycleMs: Int?
    /// Brand selector (e.g. `"connect"` / `"zerohash"`). The brand is the
    /// single source of the dot palette + footer mark; there is no separate
    /// `colors` field (matching `resolveOverlayOptions`, which derives colors
    /// from branding). An unknown or absent value falls back to the default
    /// brand during resolution (`Brand.normalize`).
    let branding: String?

    /// Lift the decoded wire shape into the resolution-layer `Partial`
    /// without applying any defaults — defaults are the job of
    /// `OverlayOptions(resolving:)`, which a later task calls.
    var asPartial: OverlayOptions.Partial {
        OverlayOptions.Partial(
            titles: titles,
            subtitles: subtitles,
            cycleMs: cycleMs,
            branding: branding
        )
    }
}

/// Per-call options that ride alongside (not inside) `payload`, mirroring the
/// wire contract `ZeroAuthRequestOptions` (contract.ts:47-60). Only
/// `overlayOptions` and `initialOverlay` are consumed today; the remaining keys
/// (presentation, …) are intentionally not decoded yet but must not break
/// decoding when present — extra JSON keys are ignored by `Codable`.
struct RequestOptions: Codable, Equatable {
    let overlayOptions: WireOverlayOptions?
    /// Whether the branded loading overlay paints over the target page while
    /// the op runs (contract.ts:38-41). Pass false when the user should watch
    /// the underlying page from the start. Optional so an absent field decodes
    /// fine; the TRUE default (extension default) is resolved at the router,
    /// not here — keeping this DTO a faithful mirror of the wire shape.
    let initialOverlay: Bool?

    init(overlayOptions: WireOverlayOptions?, initialOverlay: Bool? = nil) {
        self.overlayOptions = overlayOptions
        self.initialOverlay = initialOverlay
    }
}

// MARK: - Request

struct ZeroAuthRequest: Codable, Equatable {
    let id: String
    let role: String
    let platform: String
    let operation: String
    let payload: JSONValue?
    // Optional per-call options sibling of `payload`. Absent on most requests;
    // when present we currently only read `overlayOptions`.
    let options: RequestOptions?
    let sessionId: String?

    init(id: String, role: String = WireRole.host, platform: String, operation: String,
         payload: JSONValue? = nil, options: RequestOptions? = nil, sessionId: String? = nil) {
        self.id = id
        self.role = role
        self.platform = platform
        self.operation = operation
        self.payload = payload
        self.options = options
        self.sessionId = sessionId
    }
}

// MARK: - Response

struct ZeroAuthResponse: Codable, Equatable {
    let id: String
    let role: String
    let success: Bool
    let data: JSONValue?
    let error: String?
    let sessionId: String?
    /// Whether the front-end may safely retry the same operation
    /// (mirrors `retryable` on the wire ZeroAuthResponse, contract.ts).
    let retryable: Bool

    init(id: String, success: Bool, data: JSONValue?, error: String?, sessionId: String?, retryable: Bool = false) {
        self.id = id
        self.role = WireRole.native
        self.success = success
        self.data = data
        self.error = error
        self.sessionId = sessionId
        self.retryable = retryable
    }
}

// MARK: - Out-of-band event

struct BridgeEvent: Codable, Equatable {
    let correlationId: String
    let type: String
    let data: JSONValue?
}
