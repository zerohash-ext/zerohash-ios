// AUTH-3960 — dismissNetworkWarning, ported from PR #89's dismiss-network-warning.test.ts.
//
// The acknowledge must be resolved through the LIVE finder (never a raw
// querySelector), the dismissal confirmed by the flow actually advancing past the
// warning, and a stuck warning must NOT throw — the selection loop owns the retry
// budget, so the phase keeps exactly one failure point.
import assert from "node:assert";
import { test } from "node:test";
import {
  loadSelection,
  l2Step,
  amountStep,
  warningBody,
  advanceToAmount
} from "./withdraw-selection-shim.mjs";

const ackButton = (document) =>
  document.querySelector('[data-testid="network-warning-step-understand"]');

test("dismissNetworkWarning: acknowledges the warning and confirms the flow advanced", async () => {
  const { internals, document } = loadSelection();
  document.setContent(l2Step(warningBody()));
  ackButton(document).addEventListener("click", () => setTimeout(() => advanceToAmount(document), 40));

  await internals.dismissNetworkWarning({ clearMs: 2000 });

  assert.strictEqual(internals.findNetworkWarningAck({ allowFallback: true }), null);
  assert.strictEqual(
    await internals.detectNextScreen({ notStep: "l2SelectionStep", timeoutMs: 300 }),
    "amount"
  );
});

// Coinbase binds on pointerdown and re-renders mid-transition, so a first click can
// land on a node about to be replaced. Verifying the dismissal is what lets us retry.
test("dismissNetworkWarning: retries the click when the first one doesn't take", async () => {
  const { internals, document } = loadSelection();
  document.setContent(l2Step(warningBody()));
  let clicks = 0;
  ackButton(document).addEventListener("click", () => {
    clicks += 1;
    if (clicks >= 2) advanceToAmount(document);
  });

  await internals.dismissNetworkWarning({ clearMs: 300 });

  assert.strictEqual(clicks, 2);
  assert.strictEqual(internals.findNetworkWarningAck({ allowFallback: true }), null);
});

// The selection loop owns the retry budget, so a stuck warning must NOT throw here.
test("dismissNetworkWarning: returns without throwing when the warning never clears", async () => {
  const warns = [];
  const { internals, document } = loadSelection({
    console: { warn: (...a) => warns.push(a.join(" ")), log() {}, error() {} }
  });
  document.setContent(l2Step(warningBody()));
  let clicks = 0;
  ackButton(document).addEventListener("click", () => {
    clicks += 1;
  });

  await assert.doesNotReject(internals.dismissNetworkWarning({ clearMs: 150 }));

  assert.strictEqual(clicks, 2);
  assert.match(warns.join(" "), /not confirmed dismissed/);
});

// The live finder must skip a stale node from a faded container and click the live one.
test("dismissNetworkWarning: clicks the live acknowledge button, never a faded duplicate", async () => {
  const { internals, document } = loadSelection();
  document.setContent(l2Step(warningBody(), "inactive"), l2Step(warningBody()));
  const [stale, live] = document.querySelectorAll('[data-testid="network-warning-step-understand"]');
  let staleClicks = 0;
  let liveClicks = 0;
  stale.addEventListener("click", () => {
    staleClicks += 1;
  });
  live.addEventListener("click", () => {
    liveClicks += 1;
    advanceToAmount(document);
  });

  await internals.dismissNetworkWarning({ clearMs: 300 });

  assert.strictEqual(staleClicks, 0);
  assert.strictEqual(liveClicks, 1);
});

test("dismissNetworkWarning: is a no-op when the warning never appeared", async () => {
  const { internals, document } = loadSelection();
  document.setContent(amountStep());
  await assert.doesNotReject(internals.dismissNetworkWarning({ findMs: 150 }));
});

// Acknowledging one transfer must not silence Coinbase's account-wide loss-prevention
// warning on the user's own manual sends.
test("dismissNetworkWarning: leaves the 'don't show again' checkbox untouched", async () => {
  const { internals, document } = loadSelection();
  document.setContent(l2Step(warningBody()));
  ackButton(document).addEventListener("click", () => advanceToAmount(document));

  await internals.dismissNetworkWarning({ clearMs: 300 });

  const box = document.querySelector('[data-testid="dont-show-again"]');
  assert.strictEqual(box.checked, false);
});
