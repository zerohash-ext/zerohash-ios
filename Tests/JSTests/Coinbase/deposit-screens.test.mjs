// get-deposit-address.js + a fake coinbase-screens.js (AUTH-4657), iOS.
import assert from "node:assert";
import { test } from "node:test";
import { loadDeposit, SEL } from "./deposit-shim.mjs";
import { realGuard } from "./screens-gate-shim.mjs";

const PARAMS = { asset: "ETH", network: "ethereum" };
const WAIT_MS = 60;

function fakeScreens({ watch = null, after = null } = {}) {
  const calls = { reset: 0, confirm: 0, asked: [] };
  return {
    calls,
    reset: () => { calls.reset += 1; },
    confirmed: (flow, ids) => {
      calls.asked.push({ flow, ids: [...ids] });
      return watch && ids.includes(watch) ? watch : null;
    },
    confirm: async (flow, ids) => {
      calls.confirm += 1;
      return after && ids.includes(after) ? after : null;
    },
    guard: realGuard(),
  };
}

test("the screen fails the call with RECEIVE_UNAVAILABLE, fast, asking only about mapped ids", async () => {
  const screens = fakeScreens({ watch: "unavailable" });
  const { started } = loadDeposit({ present: [] }, PARAMS, null, screens);
  const t0 = Date.now();
  await assert.rejects(started, (e) => e.message === "RECEIVE_UNAVAILABLE");
  assert.ok(Date.now() - t0 < 1000, `took ${Date.now() - t0}ms`);
  assert.strictEqual(screens.calls.reset, 1);
  assert.deepStrictEqual(screens.calls.asked[0], { flow: "receive", ids: ["unavailable"] });
});

test("a wait that times out on the screen becomes RECEIVE_UNAVAILABLE", async () => {
  const { started } = loadDeposit({ present: [] }, PARAMS, null, fakeScreens({ after: "unavailable" }));
  await assert.rejects(started, (e) => e.message === "RECEIVE_UNAVAILABLE");
});

test("no screen, an unmapped screen or no registry: the original error stays", async () => {
  for (const screens of [fakeScreens(), fakeScreens({ watch: "send-blocked", after: "send-blocked" }), undefined]) {
    const { started } = loadDeposit({ present: [] }, PARAMS, null, screens);
    await assert.rejects(started, /receive_entry_not_found/);
  }
});

test("once the screen ends the call, the run clicks nothing more", async () => {
  // Every step is found, so an unguarded run keeps clicking through the flow.
  const found = { click() {}, focus() {}, getAttribute: () => null, textContent: "" };
  const later = (v) => new Promise((r) => setTimeout(() => r(v), WAIT_MS));
  let clicks = 0;
  const dom = {
    $: () => found,
    waitUntil: (find) => later().then(() => find()),
    waitFor: () => later(found),
    stepPrimaryButton: () => found,
    realisticClick: () => { clicks += 1; }
  };
  const { started } = loadDeposit({ present: [] }, PARAMS, null, fakeScreens({ watch: "unavailable" }), dom);
  await assert.rejects(started, (e) => e.message === "RECEIVE_UNAVAILABLE");
  const atRejection = clicks;
  await new Promise((r) => setTimeout(r, 800));
  assert.strictEqual(clicks, atRejection, "clicks landed after the call had failed");
});

test("a halt during the address loop stops its interstitial clicks", async () => {
  // iOS's entry wait does not sweep interstitials (Android's does), so the sweep
  // that can outlive a halt here is the address loop's: it clicks the network
  // warning on every pass until the deadline.
  const UNDERSTAND = '[data-testid="network-warning-step-understand"]';
  const { started, document } = loadDeposit({
    present: [
      '[data-testid="step-assetSelection-active"]',
      SEL.assetCell("ETH"),
      '[data-testid="ethereum-network"]',
      UNDERSTAND
    ]
  }, PARAMS, null, fakeScreens({ watch: "unavailable" }));
  await assert.rejects(started, (e) => e.message === "RECEIVE_UNAVAILABLE");
  const sweeps = () => document.clicks.filter((c) => c === UNDERSTAND).length;
  const atRejection = sweeps();
  await new Promise((r) => setTimeout(r, 600));
  assert.strictEqual(sweeps(), atRejection, "interstitial clicks landed after the halt");
  assert.ok(atRejection >= 1, "the run never reached the address loop, so this proves nothing");
});

test("an IDV block keeps its code even with a screen up", async () => {
  const screens = fakeScreens({ after: "unavailable" });
  const { started } = loadDeposit({ present: [] }, PARAMS, "idv_pending", screens);
  await assert.rejects(started, (e) => e.message === "IDV_PENDING");
  assert.strictEqual(screens.calls.confirm, 0);
});

test("a slow IDV preflight still wins over a screen that is already up", async () => {
  const slowIdv = new Promise((r) => setTimeout(() => r("idv_pending"), 600));
  const { started } = loadDeposit({ present: [] }, PARAMS, slowIdv, fakeScreens({ watch: "unavailable" }));
  await assert.rejects(started, (e) => e.message === "IDV_PENDING");
});
