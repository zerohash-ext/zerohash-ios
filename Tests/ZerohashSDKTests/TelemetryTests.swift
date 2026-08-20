// Tests for the telemetry collector and stamper: envelope stamping, ordering,
// draft allowlisting, and the operation→flow mapping.

import Foundation
import Testing
@testable import ZerohashSDK

@MainActor
struct TelemetryTests {
    private func str(_ v: JSONValue?) -> String? {
        if case .string(let s)? = v { return s }
        return nil
    }
    private func num(_ v: JSONValue?) -> Double? {
        if case .number(let n)? = v { return n }
        return nil
    }
    private func obj(_ v: JSONValue) -> [String: JSONValue]? {
        if case .object(let o) = v { return o }
        return nil
    }

    @Test("stamper stamps the base envelope and renumbers seq")
    func stampsBaseEnvelope() {
        let collector = TelemetryCollector()
        collector.pushDraftJson(#"{"event_name":"extension_handler_phase_reached","phase":"open-modal","at":1000,"seq":1,"realm":"injected"}"#)
        collector.emitNative(telemetrySettledRow(outcome: "success", totalMs: 42))

        let rows = collector.build(dims: TelemetryDims(
            requestId: "req-1", platformId: "cbase", operation: "getDepositAddress", flow: "single_shot"))
        #expect(rows.count == 2)

        // Injected draft at=1000 precedes the native settle row (at=now).
        guard let first = obj(rows[0]), let second = obj(rows[1]) else {
            Issue.record("rows are not objects"); return
        }
        #expect(str(first["event_name"]) == "extension_handler_phase_reached")
        #expect(str(first["phase"]) == "open-modal")
        #expect(str(first["source"]) == "sdk-ios")
        #expect(str(first["schema_version"]) == "1.0")
        #expect(str(first["browser"]) == "unknown")
        #expect(str(first["extension_version"])?.hasPrefix("ios-") == true)
        #expect(str(first["platform_id"]) == "cbase")
        #expect(str(first["operation"]) == "getDepositAddress")
        #expect(str(first["flow"]) == "single_shot")
        #expect(str(first["request_id"]) == "req-1")
        #expect(str(first["realm"]) == "injected")
        #expect(num(first["seq"]) == 1)
        // No PII columns leaked into the envelope.
        #expect(first["tab_id"] == .null)

        #expect(str(second["event_name"]) == "extension_request_settled")
        #expect(str(second["realm"]) == "background")
        #expect(num(second["total_ms"]) == 42)
        #expect(num(second["seq"]) == 2)
    }

    @Test("injected drafts are allowlisted: PII fields and forged events are dropped")
    func sanitizesInjectedDrafts() {
        let collector = TelemetryCollector()
        // A hostile draft: a legit event name carrying smuggled PII columns.
        collector.pushDraftJson(#"""
        {"event_name":"extension_handler_phase_reached","phase":"open-modal","note":"ok",
         "amount":"0.5","address":"0xdeadbeef","recipient":"Jane Doe","otp":"123456",
         "at":1000,"seq":1,"realm":"injected"}
        """#)
        // A forged event name is dropped whole.
        collector.pushDraftJson(#"{"event_name":"exfil","address":"0xabc","at":2000,"seq":2,"realm":"injected"}"#)

        let rows = collector.build(dims: TelemetryDims(requestId: "r", platformId: "cbase", operation: "op"))
        #expect(rows.count == 1) // the forged-event draft never made it in
        guard let row = obj(rows[0]) else { Issue.record("row not an object"); return }
        #expect(str(row["event_name"]) == "extension_handler_phase_reached")
        #expect(str(row["phase"]) == "open-modal")
        #expect(str(row["note"]) == "ok")
        // The smuggled PII columns were stripped before stamping.
        #expect(row["amount"] == nil)
        #expect(row["address"] == nil)
        #expect(row["recipient"] == nil)
        #expect(row["otp"] == nil)
    }

    @Test("timeline is ordered by (at, realmRank, seq) with seq renumbered 1..N")
    func ordersTimeline() {
        let collector = TelemetryCollector()
        // Pushed out of order; build must sort ascending by `at`. Distinguished by
        // `phase` since the draft schema admits one event name (see InjectedDraft).
        collector.pushDraftJson(#"{"event_name":"extension_handler_phase_reached","phase":"b","at":2000,"seq":5,"realm":"injected"}"#)
        collector.pushDraftJson(#"{"event_name":"extension_handler_phase_reached","phase":"a","at":1000,"seq":9,"realm":"injected"}"#)

        let rows = collector.build(dims: TelemetryDims(requestId: "r", platformId: "cbase", operation: "op"))
        #expect(rows.count == 2)
        #expect(str(obj(rows[0])?["phase"] ?? .null) == "a")
        #expect(str(obj(rows[1])?["phase"] ?? .null) == "b")
        #expect(num(obj(rows[0])?["seq"] ?? .null) == 1)
        #expect(num(obj(rows[1])?["seq"] ?? .null) == 2)
    }

    @Test("an empty collector builds nothing")
    func emptyBuild() {
        let collector = TelemetryCollector()
        #expect(collector.isEmpty)
        #expect(collector.build(dims: TelemetryDims(requestId: "r", platformId: "p", operation: "o")).isEmpty)
    }

    @Test("flow is derived from the operation name")
    func flowDerivation() {
        #expect(AutomationWebViewMessageRouter.telemetryFlow(for: "withdraw.start") == "session_open")
        #expect(AutomationWebViewMessageRouter.telemetryFlow(for: "withdraw.continue") == "session_continue")
        #expect(AutomationWebViewMessageRouter.telemetryFlow(for: "withdraw.cancel") == "session_close")
        #expect(AutomationWebViewMessageRouter.telemetryFlow(for: "getBalance") == "single_shot")
        #expect(AutomationWebViewMessageRouter.telemetryFlow(for: "getDepositAddress") == "single_shot")
    }
}
