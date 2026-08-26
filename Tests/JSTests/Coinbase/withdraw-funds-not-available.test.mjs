import assert from "node:assert";
import { test } from "node:test";
import { loadWithdraw, SEL } from "./withdraw-shim.mjs";

const REJECTED_HOLD = { state: "rejected", reason: "funds_not_available" };

function assertHoldRejection(state) {
  assert.deepStrictEqual({ ...state }, REJECTED_HOLD);
  assert.ok(!("fundsAvailability" in state), "fundsAvailability must be omitted, not null-filled");
}

test("the hold step is detected by its container", () => {
  const { internals } = loadWithdraw({ present: [SEL.STEP_WBL_HOLD] });
  assert.strictEqual(internals.isHoldModalPresent(), true);
});

test("a zero-crypto empty state is not mistaken for a hold", () => {
  const { internals } = loadWithdraw({ present: ['[data-testid="no-crypto-title"]'] });
  assert.strictEqual(internals.isHoldModalPresent(), false);
});

test("the recipient wait rejects immediately when the hold step is up", async () => {
  const { internals } = loadWithdraw({ present: [SEL.STEP_WBL_HOLD] });
  await assert.rejects(internals.awaitRecipientOrPendingBlock(), (err) => {
    assert.strictEqual(err.zhFundsNotAvailable, true);
    assert.match(err.message, /^withdraw\/funds-not-available:/);
    return true;
  });
});

test("a blocking prior transfer still outranks the hold step", async () => {
  const { internals } = loadWithdraw({
    present: [SEL.STEP_PREVIOUS_TRANSFER, SEL.STEP_WBL_HOLD]
  });
  await assert.rejects(internals.awaitRecipientOrPendingBlock(), (err) => {
    assert.ok(err.zhPendingTransfer, "expected the pending-transfer tag to win");
    assert.strictEqual(err.zhFundsNotAvailable, undefined);
    return true;
  });
});

test("a present recipient field wins over a stale hold step", async () => {
  const { internals } = loadWithdraw({
    present: [SEL.RECIPIENT_INPUT, SEL.STEP_WBL_HOLD]
  });
  await assert.doesNotReject(internals.awaitRecipientOrPendingBlock());
});

test("continue classifies a step failure as funds_not_available while the hold is up", async () => {
  const { window, internals } = loadWithdraw({ present: [SEL.STEP_WBL_HOLD] });
  assert.strictEqual(internals.isHoldModalPresent(), true);

  const state = await window.__zhWithdraw.continue({ kind: "otp", code: "not-a-code" });
  assertHoldRejection(state);
});

test("continue rethrows the original error when the hold is not up", async () => {
  const { window } = loadWithdraw();
  await assert.rejects(
    window.__zhWithdraw.continue({ kind: "otp", code: "not-a-code" }),
    /withdraw\/invalid-payload: code/
  );
});

test("start surfaces the hold as a rejection rather than a selector timeout", async () => {
  const { window } = loadWithdraw({
    present: [SEL.QUICK_ACTION_SEND, SEL.STEP_WBL_HOLD]
  });
  const state = await window.__zhWithdraw.start({ address: "0xabc", asset: "USDC", amount: "max" });
  assertHoldRejection(state);
});
