import assert from "node:assert";
import { test } from "node:test";
import { readFileSync } from "node:fs";
import { loadWithdraw, rehome } from "./withdraw-shim.mjs";

const classifySendEntry = loadWithdraw().internals.classifySendEntry;

const WITHDRAW_SOURCE = readFileSync(
  new URL("../../../Sources/ZerohashSDK/Platforms/Coinbase/withdraw.js", import.meta.url),
  "utf8"
);

const entry = (overrides = {}) =>
  rehome(
    classifySendEntry({
      recipient: false,
      previousTransfer: false,
      holdModal: false,
      ...overrides,
    }) ?? { entry: null }
  );

test("a mounted recipient step is entered directly", () => {
  assert.deepStrictEqual(entry({ recipient: true }), { entry: "deep-link" });
});

test("a recipient step outranks a blocker", () => {
  assert.deepStrictEqual(
    entry({ recipient: true, previousTransfer: true, holdModal: true }),
    { entry: "deep-link" }
  );
});

test("a prior transfer blocking the send is reported on landing", () => {
  assert.deepStrictEqual(entry({ previousTransfer: true }), { entry: "pending-transfer" });
});

test("a funds-on-hold modal is reported", () => {
  assert.deepStrictEqual(entry({ holdModal: true }), { entry: "funds-not-available" });
});

test("nothing recognised yet keeps the poll waiting", () => {
  assert.strictEqual(
    classifySendEntry({ recipient: false, previousTransfer: false, holdModal: false }),
    null
  );
});

test("no dashboard click-through remains in the asset", () => {
  for (const gone of [
    "findSendTrigger",
    "openSendModalStandard",
    "openSendModalAdvance",
    "QUICK_ACTION_SEND",
    "TRANSFER_DROPDOWN_BUTTON",
    "BOTTOM_DRAWER_BUTTON",
    "ICON_SEND_CRYPTO",
  ]) {
    assert.ok(!WITHDRAW_SOURCE.includes(gone), gone + " should be gone");
  }
});

test("failing to mount names the URL and the selector", () => {
  assert.ok(WITHDRAW_SOURCE.includes("withdraw/send-step-not-mounted"));
  assert.ok(WITHDRAW_SOURCE.includes('SEND_URL + " " + SEL.RECIPIENT_INPUT'));
});

test("the entry decision is exposed for the flow to use", () => {
  const { internals } = loadWithdraw();
  assert.strictEqual(typeof internals.classifySendEntry, "function");
  assert.strictEqual(typeof internals.probeSendEntry, "function");
});
