// Telemetry buffer injected before every automation script when telemetry is on.
// Each breadcrumb posts live to the `zhTelemetry` handler. Never emits PII.
window.__zhTelemetry = window.__zhTelemetry || (function () {
  var seq = 0;
  var enabled = false;
  var phaseIndex = 0;
  var dispatchStart = 0;
  // Capture Date.now before page code can shim it (same reasoning as the native
  // clock captures in the extension's injected runtime).
  var nativeNow = Date.now.bind(Date);

  // Redaction backstop. Coinbase puts addresses in data-testid, so the free-text
  // fields are scrubbed inside emit where no call site can skip it.
  var ADDRESS_RE = /0x[a-fA-F0-9]{6,}|\b[a-km-zA-HJ-NP-Z1-9]{26,}\b/g; // hex / base58
  var AMOUNT_RE = /\b\d+\.\d+\b/g; // amounts
  var REDACTED_FIELDS = ["note", "phase", "failure_code"];

  function scrub(text) {
    return text.replace(ADDRESS_RE, "[redacted]").replace(AMOUNT_RE, "[redacted]");
  }

  function post(row) {
    try {
      var mh = window.webkit &&
        window.webkit.messageHandlers &&
        window.webkit.messageHandlers.zhTelemetry;
      if (mh) mh.postMessage(JSON.stringify(row));
    } catch (e) {}
  }

  return {
    // Native calls enable(true) once per dispatch, which also resets the phase
    // counter so each dispatch has a fresh timeline.
    enable: function (on) {
      enabled = !!on;
      if (enabled) { phaseIndex = 0; dispatchStart = nativeNow(); }
    },
    isEnabled: function () { return enabled; },
    emit: function (input) {
      if (!enabled) return;
      var row = {};
      for (var k in input) {
        if (Object.prototype.hasOwnProperty.call(input, k)) row[k] = input[k];
      }
      row.at = nativeNow();
      row.seq = ++seq;
      row.realm = "injected";
      for (var i = 0; i < REDACTED_FIELDS.length; i++) {
        var f = REDACTED_FIELDS[i];
        if (typeof row[f] === "string") row[f] = scrub(row[f]);
      }
      post(row);
    },
    // A milestone in the flow, emitting extension_handler_phase_reached. `note` is
    // an optional short tag (never PII).
    breadcrumb: function (phase, note) {
      if (!enabled) return;
      this.emit({
        event_name: "extension_handler_phase_reached",
        phase: String(phase),
        note: (note === undefined || note === null) ? null : String(note),
        phase_index: ++phaseIndex,
        since_dispatch_ms: nativeNow() - dispatchStart
      });
    },
    // Present for API symmetry with Android; iOS posts live, so there is nothing
    // to drain.
    drain: function () { return []; }
  };
})();
