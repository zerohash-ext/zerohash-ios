// AUTH-3960 — runSelectionPhase, ported from PR #89's selection-phase.test.ts.
//
// The reported failure was a SECOND sighting of the acceptance warning being fatal
// (`withdraw/selection-phase-stalled: revisited networkWarning`). Coinbase can
// chain interstitials and our own acknowledge can be re-read while the container
// fades, so the warning is tolerated up to a cap; network/coin stay single-shot
// because re-running them could pick a DIFFERENT network or asset. A wall-clock
// budget bounds the whole phase.
//
// runSelectionPhase takes `opts.detect` / `opts.handlers` test seams that default
// to the real collaborators (prod is unchanged); here we script the screens and
// spy the handlers, so no DOM is needed.
import assert from "node:assert";
import { test } from "node:test";
import { loadSelection } from "./withdraw-selection-shim.mjs";

const PAYLOAD = {
  address: "0xBaCc952a0b88Af94c66e6B67b57622d5f220cE42",
  asset: "ETH",
  network: "base",
  amount: { value: "0.01", currency: "crypto" }
};

// Builds a scripted detect + spy handlers. `detect` shifts screens off the array
// and records the opts it was called with.
function harness(screens, { detectDelayMs = 0 } = {}) {
  const calls = [];
  const detectOpts = [];
  const detect = (opts = {}) => {
    detectOpts.push(opts);
    const next = screens.shift();
    if (!next) throw new Error("test: detect called more often than scripted");
    if (detectDelayMs) {
      return new Promise((r) => setTimeout(() => r(next), detectDelayMs));
    }
    return Promise.resolve(next);
  };
  const mk = (name, step) => ({
    run: () => {
      calls.push(name);
      return Promise.resolve();
    },
    step
  });
  const handlers = {
    coin: mk("selectCoin", "assetSelection"),
    network: mk("selectNetwork", "l2SelectionStep"),
    networkWarning: mk("dismissNetworkWarning", "l2SelectionStep"),
    destinationTag: mk("skipDestinationTag", "destinationTagStep")
  };
  return { calls, detectOpts, detect, handlers };
}

const run = (screens, opts = {}) => {
  const { internals } = loadSelection();
  const h = harness(screens, opts);
  return { h, promise: internals.runSelectionPhase(PAYLOAD, { detect: h.detect, handlers: h.handlers, ...opts }) };
};

test("runSelectionPhase: drives coin → network → warning → amount and threads notStep", async () => {
  const { h, promise } = run(["coin", "network", "networkWarning", "amount"]);
  await promise;
  assert.deepStrictEqual(h.calls, ["selectCoin", "selectNetwork", "dismissNetworkWarning"]);
  assert.deepStrictEqual(h.detectOpts.map((o) => o.notStep), [
    undefined,
    "assetSelection",
    "l2SelectionStep",
    "l2SelectionStep"
  ]);
});

test("runSelectionPhase: skips straight to amount when Coinbase asks for nothing", async () => {
  const { h, promise } = run(["amount"]);
  await promise;
  assert.deepStrictEqual(h.calls, []);
});

test("runSelectionPhase: tolerates the acceptance warning appearing more than once", async () => {
  const { h, promise } = run(["network", "networkWarning", "networkWarning", "amount"]);
  await promise;
  assert.deepStrictEqual(h.calls, ["selectNetwork", "dismissNetworkWarning", "dismissNetworkWarning"]);
});

test("runSelectionPhase: fails once the warning exceeds its attempt cap", async () => {
  const { promise } = run(["networkWarning", "networkWarning", "networkWarning", "networkWarning"]);
  await assert.rejects(promise, /revisited networkWarning 4× \(cap 3\)/);
});

test("runSelectionPhase: fails immediately on a revisited network, without re-running the handler", async () => {
  const { h, promise } = run(["network", "network"]);
  await assert.rejects(promise, /revisited network 2× \(cap 1\)/);
  assert.deepStrictEqual(h.calls, ["selectNetwork"]);
});

test("runSelectionPhase: fails immediately on a revisited coin selection", async () => {
  const { h, promise } = run(["coin", "coin"]);
  await assert.rejects(promise, /revisited coin 2× \(cap 1\)/);
  assert.deepStrictEqual(h.calls, ["selectCoin"]);
});

test("runSelectionPhase: clamps the detect timeout to the remaining budget when it is smaller", async () => {
  const { h, promise } = run(["amount"], { budgetMs: 5000 });
  await promise;
  assert.ok(h.detectOpts[0].timeoutMs <= 5000 && h.detectOpts[0].timeoutMs > 4500);
});

// withdraw.start has no request timeout, so this wall-clock budget is the only thing
// guaranteeing the host ever gets an answer now that the caps no longer pin every
// screen at one. Each detect burns ~120ms; a 50ms budget is exhausted after the first.
test("runSelectionPhase: gives up when the phase budget is exhausted", async () => {
  const { h, promise } = run(["networkWarning", "networkWarning"], {
    budgetMs: 50,
    detectDelayMs: 120
  });
  await assert.rejects(promise, /budget exhausted \(networkWarning×1\)/);
  assert.strictEqual(h.detectOpts.length, 1);
});
