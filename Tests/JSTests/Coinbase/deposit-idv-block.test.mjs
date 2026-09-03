import assert from "node:assert";
import { test } from "node:test";
import { loadDeposit, SEL } from "./deposit-shim.mjs";

const cell = (a) => SEL.assetCell(a);

test("a blocked account fails with the IDV code instead of blaming the asset", async () => {
  const { internals } = loadDeposit(
    { present: [SEL.SEARCH_INPUT] },
    { asset: "USDC" },
    "idv_pending"
  );

  const err = await internals.pickAsset().then(
    () => null,
    (e) => e
  );

  assert.ok(err, "the asset wait must not resolve on a blocked account");
  assert.strictEqual(
    err.message,
    "IDV_PENDING",
    "the message IS the wire error code, so the host can match on it"
  );
});

test("a failed-document account reports IDV_FAILED from the same site", async () => {
  const { internals } = loadDeposit(
    { present: [SEL.SEARCH_INPUT] },
    { asset: "USDC" },
    "idv_failed"
  );

  const err = await internals.pickAsset().then(
    () => null,
    (e) => e
  );

  assert.strictEqual(err.message, "IDV_FAILED");
});

test("a genuinely unavailable asset still reports asset_not_available", async () => {
  const { internals } = loadDeposit(
    { present: [SEL.SEARCH_INPUT] },
    { asset: "DOGE" },
    null
  );

  const err = await internals.pickAsset().then(
    () => null,
    (e) => e
  );

  assert.match(err.message, /asset_not_available:DOGE/);
});

test("an absent gate leaves the asset failure exactly as it was", async () => {
  const { internals } = loadDeposit({ present: [SEL.SEARCH_INPUT] }, { asset: "DOGE" });

  const err = await internals.pickAsset().then(
    () => null,
    (e) => e
  );

  assert.match(err.message, /asset_not_available:DOGE/);
});

test("a healthy account is untouched by the block check", async () => {
  const { internals, document } = loadDeposit(
    { present: [cell("BTC"), SEL.SEARCH_INPUT] },
    { asset: "BTC" },
    null
  );

  await internals.pickAsset();

  assert.deepStrictEqual(document.clicks, [cell("BTC")]);
});
