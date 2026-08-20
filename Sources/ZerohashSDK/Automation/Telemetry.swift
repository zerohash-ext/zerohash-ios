import Foundation
import WebKit

// Telemetry for the scraping automation. Builds plain-JSON rows and sends them on
// the response to Faro. Off by default; never carries amount/address/OTP/recipient.

/// Master gate; default OFF. Set true to force telemetry regardless of the
/// per-request opt-in (parity with Android's `TelemetryConfig.enabled`).
enum TelemetryConfig {
    @MainActor static var enabled = false
}

/// Holds the collector for the current operation. The router sets it; the
/// `zhTelemetry` handler writes drafts to it. One operation runs at a time.
@MainActor
enum TelemetryRouter {
    static var collector: TelemetryCollector?
}

/// Request-level dimensions only native knows, stamped onto every row.
struct TelemetryDims {
    let requestId: String
    /// Wire `platform`, e.g. `"cbase"` / `"kraken"`.
    let platformId: String
    /// Operation name, e.g. `"getBalance"` / `"withdraw.start"`.
    let operation: String
    /// Withdraw session id when in a multi-step session, else nil.
    var zeroauthSessionId: String? = nil
    /// `single_shot` / `session_open` / `session_continue` / `session_close`.
    var flow: String? = nil
    /// `tab` / `popup` on the extension; nil on mobile.
    var presentation: String? = nil
    /// `retail` / `advanced` / `unknown`, observed from the page when available.
    var surface: String? = nil
}

/// The row native emits once per request (the extension's
/// `extension_request_settled`). Covers success, error, and timeout.
func telemetrySettledRow(outcome: String, totalMs: Int) -> [String: JSONValue] {
    [
        "event_name": .string("extension_request_settled"),
        "outcome": .string(outcome),
        "total_ms": .number(Double(totalMs)),
        "dropped_events": .number(0),
    ]
}

/// The one shape the page may post. The `zhTelemetry` handler is open to any page
/// script, so decoding into this struct drops every field we don't declare.
private struct InjectedDraft: Decodable {
    /// Our scripts emit exactly one event, via `__zhTelemetry.breadcrumb`. Any other
    /// event_name (a forged type) is dropped whole.
    static let allowedEvent = "extension_handler_phase_reached"
    /// Blurt guard: cap strings so a field can't smuggle a large payload.
    static let maxStringLength = 256

    let event_name: String
    let phase: String?
    let note: String?
    let phase_index: Double?
    let since_dispatch_ms: Double?
    let at: Double?
    let seq: Double?

    /// The allowlisted draft as a stampable row, or nil to drop it whole.
    func row() -> [String: JSONValue]? {
        guard event_name == Self.allowedEvent else { return nil }
        var out: [String: JSONValue] = ["event_name": .string(event_name)]
        if let phase { out["phase"] = .string(String(phase.prefix(Self.maxStringLength))) }
        if let note { out["note"] = .string(String(note.prefix(Self.maxStringLength))) }
        if let phase_index { out["phase_index"] = .number(phase_index) }
        if let since_dispatch_ms { out["since_dispatch_ms"] = .number(since_dispatch_ms) }
        if let at { out["at"] = .number(at) }
        if let seq { out["seq"] = .number(seq) }
        out["realm"] = .string("injected") // an injected draft is always injected-realm
        return out
    }
}

/// Buffers this dispatch's rows. The handler feeds [pushDraftJson], native rows feed
/// [emitNative], and [build] stamps them at the end. Runs on the main thread.
@MainActor
final class TelemetryCollector {
    private var rows: [[String: JSONValue]] = []
    private var nativeSeq = 0

    /// Take one draft posted by telemetry.js. Untrusted (see [InjectedDraft]):
    /// decoding keeps only declared fields, and a forged event is dropped.
    func pushDraftJson(_ json: String) {
        guard let data = json.data(using: .utf8),
              let draft = try? JSONDecoder().decode(InjectedDraft.self, from: data),
              let row = draft.row() else { return }
        rows.append(row)
    }

    /// Emit a native (realm `background`) row — the framework settle row, and the
    /// no-script / timeout / load-error paths where the injected realm never ran.
    func emitNative(_ fields: [String: JSONValue]) {
        var f = fields
        f["at"] = .number(Date().timeIntervalSince1970 * 1000)
        nativeSeq += 1
        f["seq"] = .number(Double(nativeSeq))
        f["realm"] = .string("background")
        rows.append(f)
    }

    var isEmpty: Bool { rows.isEmpty }

    func build(dims: TelemetryDims) -> [JSONValue] {
        TelemetryStamper.build(drafts: rows, dims: dims)
    }
}

/// Promotes DRAFT rows to full wire rows conforming to the extension's base envelope.
enum TelemetryStamper {
    static let source = "sdk-ios" // Loki discriminator; the extension uses "extension"
    static let schemaVersion = "1.0"
    static let browser = "unknown" // existing enum member; platform is carried by SOURCE

    // background < content-script < injected — the extension's causal ordering.
    private static let realmRank = ["background": 0, "content-script": 1, "injected": 2]

    private static func num(_ d: [String: JSONValue], _ key: String) -> Double {
        if case .number(let n)? = d[key] { return n }
        return 0
    }

    private static func realm(_ d: [String: JSONValue]) -> String {
        if case .string(let s)? = d["realm"] { return s }
        return "injected"
    }

    /// Sort [drafts] into one timeline by `(at, realmRank, seq)`, renumber `seq`
    /// from 1, and stamp the base fields.
    static func build(drafts: [[String: JSONValue]], dims: TelemetryDims) -> [JSONValue] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Stable sort via an original-index tiebreak (Swift's sort isn't stable).
        let ordered = drafts.enumerated().sorted { lhs, rhs in
            let la = num(lhs.element, "at"), ra = num(rhs.element, "at")
            if la != ra { return la < ra }
            let lr = realmRank[realm(lhs.element)] ?? 2
            let rr = realmRank[realm(rhs.element)] ?? 2
            if lr != rr { return lr < rr }
            let ls = num(lhs.element, "seq"), rs = num(rhs.element, "seq")
            if ls != rs { return ls < rs }
            return lhs.offset < rhs.offset
        }.map(\.element)

        var out: [JSONValue] = []
        for (i, draft) in ordered.enumerated() {
            let at = num(draft, "at")
            var row: [String: JSONValue] = [:]
            // Event-specific fields the draft carried (event_name + its own fields).
            for (key, value) in draft where key != "at" && key != "seq" && key != "realm" {
                row[key] = value
            }
            row["event_id"] = .string(UUID().uuidString)
            row["source"] = .string(source)
            row["schema_version"] = .string(schemaVersion)
            row["timestamp"] = .string(iso.string(from: Date(timeIntervalSince1970: at / 1000.0)))
            row["at"] = .number(at)
            row["seq"] = .number(Double(i + 1))
            row["realm"] = .string(realm(draft))
            row["request_id"] = .string(dims.requestId)
            row["dispatch_id"] = draft["dispatch_id"] ?? .null
            row["extension_version"] = .string("ios-\(ZerohashSDK.version)")
            row["browser"] = .string(browser)
            row["platform_id"] = .string(dims.platformId)
            row["operation"] = .string(dims.operation)
            row["flow"] = dims.flow.map(JSONValue.string) ?? .null
            row["presentation"] = dims.presentation.map(JSONValue.string) ?? .null
            row["surface"] = dims.surface.map(JSONValue.string) ?? .null
            row["zeroauth_session_id"] = dims.zeroauthSessionId.map(JSONValue.string) ?? .null
            row["tab_id"] = .null
            out.append(.object(row))
        }
        return out
    }
}

/// Loads `telemetry.js` once and builds the per-injection install prelude.
enum TelemetryInstall {
    private static let js: String = {
        guard let url = Bundle.module.url(forResource: "telemetry", withExtension: "js"),
              let body = try? String(contentsOf: url, encoding: .utf8)
        else {
            assertionFailure("telemetry.js missing from SDK bundle")
            return ""
        }
        return body
    }()

    /// Script prepended before every automation script when telemetry is on. Empty
    /// when off, so an off dispatch injects nothing.
    @MainActor
    static func prelude() -> String {
        guard TelemetryRouter.collector != nil else { return "" }
        return js + "\ntry { window.__zhTelemetry.enable(true); } catch (e) {}\n"
    }
}

/// The `zhTelemetry` handler on every automation WebView. Each draft is pushed to
/// the current collector on the main thread (WebKit delivers messages there).
final class TelemetryScriptMessageHandler: NSObject, WKScriptMessageHandler {
    static let shared = TelemetryScriptMessageHandler()

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let json = message.body as? String else { return }
        MainActor.assumeIsolated {
            TelemetryRouter.collector?.pushDraftJson(json)
        }
    }
}
