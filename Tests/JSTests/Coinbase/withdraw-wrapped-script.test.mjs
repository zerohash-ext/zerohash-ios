// Regression guard for two things:
//  1. The three withdraw scripts are built by concatenating dom-helpers.js and
//     withdraw.js into an IIFE (Coinbase.swift:392-401) and then wrapped in
//     `return ( … );` by the runner (AutomationSessionViewController:120-125).
//     A syntax error would only show up on a device.
//  2. (CWE-94) Request data must arrive as a bound callAsyncJavaScript argument,
//     never interpolated into the source.
import assert from "node:assert";
import { test } from "node:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const srcDir = fileURLToPath(
  new URL("../../../Sources/ZerohashSDK/Platforms/Coinbase/", import.meta.url)
);
const domHelpers = readFileSync(
  fileURLToPath(new URL("../../../Sources/ZerohashSDK/Automation/dom-helpers.js", import.meta.url)),
  "utf8"
);
const withdraw = readFileSync(srcDir + "withdraw.js", "utf8");
const swift = readFileSync(srcDir + "Coinbase.swift", "utf8");

// Mirror Coinbase.swift's string building.
const build = (call) =>
  "(function(){ " + domHelpers + "; " + withdraw + " return " + call + "; })()";

const START = build("window.__zhWithdraw.start(params)");
const CONTINUE = build("window.__zhWithdraw.continue(payload)");
const CANCEL = build("window.__zhWithdraw.cancel()");

test("the injected start script parses with params bound", () => {
  assert.doesNotThrow(() => new Function("params", "return (\n" + START + "\n);"));
});

test("the injected continue script parses with payload bound", () => {
  assert.doesNotThrow(() => new Function("payload", "return (\n" + CONTINUE + "\n);"));
});

test("the injected cancel script parses", () => {
  assert.doesNotThrow(() => new Function("return (\n" + CANCEL + "\n);"));
});

test("request data reaches the script as a bound argument, not interpolation", () => {
  assert.ok(swift.includes("window.__zhWithdraw.start(params)"),
            "startWithdrawJS must call start(params)");
  assert.ok(swift.includes("window.__zhWithdraw.continue(payload)"),
            "continueWithdrawJS must call continue(payload)");
  // A Swift interpolation would read `start(\(…))`.
  assert.ok(!/__zhWithdraw\.(start|continue)\(\\\(/.test(swift),
            "withdraw entry points must not interpolate request data");
});

test("withdraw.js installs the test seam it is expected to expose", () => {
  for (const name of ["SEL", "classifyPostConfirm", "probePostConfirm",
                      "settlePostConfirm"]) {
    assert.ok(withdraw.includes(name + ": " + name),
              "missing from __internals: " + name);
  }
});

// Returning a shared constant for either outcome would let one caller's stray
// write poison every later classification, silently, because this file is not in
// strict mode. Both factories must allocate.
//
// These are source-text patterns, so they pin the current one-line form. A benign
// reformat that still allocates could fail them spuriously — if that happens,
// loosen the pattern rather than dropping the guard.
test("the classifier's outcome factories both return fresh objects", () => {
  assert.ok(/function keepWaiting\(\)\s*\{\s*return \{/.test(withdraw),
            "keepWaiting must construct a new object, not return a shared constant");
  assert.ok(/function decide\(kind\)\s*\{\s*return \{/.test(withdraw),
            "decide must construct a new object, not return a shared or memoised one");
  assert.ok(!/var\s+UNSETTLED\s*=/.test(withdraw),
            "a shared UNSETTLED constant has been reintroduced");
});

// Criterion 5 of the spec — cancel must never abort a held transfer — rests
// entirely on these three lines, and nothing else asserted them. The only screen
// with a Coinbase cancel button is the risk screen, which is exactly when the user
// has been sent to the Coinbase app to finish an identity check, and auth-ui fires
// withdraw.cancel on modal unmount. Clicking would destroy the transfer.
test("cancel is teardown only and never clicks Coinbase's button", () => {
  assert.ok(/cancel: async function \(\) \{\s*(\/\/[^\n]*\n\s*)*return \{ cancelled: false \};/.test(withdraw),
            "cancel must unconditionally return { cancelled: false }");
  assert.ok(!/clickCancelTransfer/.test(withdraw),
            "clickCancelTransfer has been reintroduced");
});

// completeBefore went from parsed-from-the-DOM to hardcoded null: the risk screen
// carries no deadline label, and the value Coinbase does have (delayedSendDate)
// only arrives in the commit response, which this design does not read.
test("id-verification reports a null completeBefore", () => {
  assert.ok(/kind: "id-verification", details: details, completeBefore: null/.test(withdraw),
            "toState must hardcode completeBefore: null for id-verification");
  assert.ok(!/parseRiskCompleteBefore/.test(withdraw),
            "parseRiskCompleteBefore has been reintroduced");
});
