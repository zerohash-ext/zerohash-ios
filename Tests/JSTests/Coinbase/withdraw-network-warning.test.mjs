// AUTH-3960 — port of the Chrome network-acceptance-warning fix (AUTH-3941, PR #89)
// to iOS withdraw.js. Mirrors tests/.../withdraw/network-warning.test.ts.
//
// The bug (BASE deposits): after we acknowledge "Does your recipient accept ETH on
// Base?", Coinbase re-stamps the l2SelectionStep container `-inactive` but leaves
// it mounted and laid out. isVisible checks offsetParent + a non-zero rect, never
// opacity, so the acknowledge button still reads as visible — and the old
// warning-check-first ordering returned `networkWarning` a second time, which the
// selection loop treated as `withdraw/selection-phase-stalled: revisited networkWarning`.
import assert from "node:assert";
import { test } from "node:test";
import {
  loadSelection,
  l2Step,
  amountStep,
  currencyInput,
  networkCell,
  warningBody,
  ACK_LABEL,
  el
} from "./withdraw-selection-shim.mjs";

test("detectNextScreen: networkWarning when the ack button is up under l2SelectionStep with notStep set", async () => {
  const { internals, document } = loadSelection();
  document.setContent(l2Step(warningBody()));
  assert.strictEqual(
    await internals.detectNextScreen({ notStep: "l2SelectionStep" }),
    "networkWarning"
  );
});

test("detectNextScreen: amount once the warning is gone and amount entry is active", async () => {
  const { internals, document } = loadSelection();
  document.setContent(amountStep());
  assert.strictEqual(await internals.detectNextScreen({ notStep: "l2SelectionStep" }), "amount");
});

test("detectNextScreen: network (not networkWarning) when the button is absent", async () => {
  const { internals, document } = loadSelection();
  document.setContent(l2Step(networkCell("ethereum")));
  assert.strictEqual(await internals.detectNextScreen({}), "network");
});

// THE REGRESSION: an acknowledged warning still fading in an `-inactive` container
// must NOT out-rank the amount screen we actually reached.
test("detectNextScreen: reports amount, not a second networkWarning, while the acknowledged warning fades", async () => {
  const { internals, document } = loadSelection();
  document.setContent(l2Step(warningBody(), "inactive"), amountStep());
  assert.strictEqual(
    await internals.detectNextScreen({ notStep: "l2SelectionStep", timeoutMs: 500 }),
    "amount"
  );
});

// One beat earlier: the amount input has mounted but the containers aren't
// re-stamped yet, so the only `-active` step is the stale l2 (masked by notStep)
// with a live acknowledge button in it. The CURRENCY_INPUT content anchor resolves it.
test("detectNextScreen: prefers the amount content anchor over a still-visible ack button", async () => {
  const { internals, document } = loadSelection();
  document.setContent(l2Step(warningBody()), currencyInput());
  assert.strictEqual(
    await internals.detectNextScreen({ notStep: "l2SelectionStep", timeoutMs: 500 }),
    "amount"
  );
});

test("detectNextScreen: times out rather than acting on a warning that exists only in a faded container", async () => {
  const { internals, document } = loadSelection();
  document.setContent(l2Step(warningBody(), "inactive"));
  await assert.rejects(
    internals.detectNextScreen({ notStep: "l2SelectionStep", timeoutMs: 400 }),
    /no-next-screen/
  );
});

test("findNetworkWarningAck: finds the ack button in a live container", () => {
  const { internals, document } = loadSelection();
  document.setContent(l2Step(warningBody()));
  assert.notStrictEqual(internals.findNetworkWarningAck(), null);
});

test("findNetworkWarningAck: ignores an ack button inside a faded container", () => {
  const { internals, document } = loadSelection();
  document.setContent(l2Step(warningBody(), "inactive"));
  assert.strictEqual(internals.findNetworkWarningAck(), null);
  assert.strictEqual(internals.findNetworkWarningAck({ allowFallback: true }), null);
});

// Once notStep masks l2SelectionStep, the testid is the flow's ONLY exit signal,
// so a Coinbase rename would leave the loop blind. The label fallback covers that —
// and must match the CURLY apostrophe, so this asserts against ACK_LABEL.
test("findNetworkWarningAck: falls back to the button label when the testid has drifted", async () => {
  const { internals, document } = loadSelection();
  document.setContent(l2Step(warningBody({ testid: false, label: ACK_LABEL })));
  assert.strictEqual(internals.findNetworkWarningAck(), null);
  assert.notStrictEqual(internals.findNetworkWarningAck({ allowFallback: true }), null);
  assert.strictEqual(
    await internals.detectNextScreen({ notStep: "l2SelectionStep", fallbackAfterMs: 0, timeoutMs: 500 }),
    "networkWarning"
  );
});

// A live network list is never the warning — without this guard the label fallback
// could latch onto some other button while the list is still up.
test("findNetworkWarningAck: refuses the label fallback while the l2 container still holds network cells", async () => {
  const { internals, document } = loadSelection();
  document.setContent(
    l2Step([networkCell("base"), networkCell("ethereum"), el("button", {}, ACK_LABEL)])
  );
  assert.strictEqual(internals.findNetworkWarningAck({ allowFallback: true }), null);
  assert.strictEqual(
    await internals.detectNextScreen({ fallbackAfterMs: 0, timeoutMs: 500 }),
    "network"
  );
});

// The fallback is gated on a delay so it can't fire mid-transition.
test("detectNextScreen: does not fire the label fallback before fallbackAfterMs has elapsed", async () => {
  const { internals, document } = loadSelection();
  document.setContent(l2Step(warningBody({ testid: false })));
  await assert.rejects(
    internals.detectNextScreen({ notStep: "l2SelectionStep", timeoutMs: 300 }),
    /no-next-screen/
  );
});
