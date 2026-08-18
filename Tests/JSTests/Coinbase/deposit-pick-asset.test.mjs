import assert from "node:assert";
import { test } from "node:test";
import { loadDeposit, SEL } from "./deposit-shim.mjs";

const cell = (a) => SEL.assetCell(a);

const revealOnSearch = (asset) => (value, doc) => {
  if (String(value).toUpperCase() === asset) doc.present.add(cell(asset));
};

test("an asset already rendered in the list is clicked without searching", async () => {
  const { internals, document } = loadDeposit(
    { present: [cell("BTC"), SEL.SEARCH_INPUT] },
    { asset: "BTC" }
  );

  await internals.pickAsset();

  assert.deepStrictEqual(document.clicks, [cell("BTC")]);
  assert.deepStrictEqual(document.typed, []);
});

test("an asset below the fold is found by typing it into the search box", async () => {
  const { internals, document } = loadDeposit(
    { present: [SEL.SEARCH_INPUT], onSearch: revealOnSearch("SOL") },
    { asset: "SOL" }
  );

  await internals.pickAsset();

  assert.deepStrictEqual(document.typed, ["SOL"]);
  assert.deepStrictEqual(document.clicks, [cell("SOL")]);
});

test("typing dispatches the events React needs to re-render", async () => {
  const { internals, document } = loadDeposit(
    { present: [SEL.SEARCH_INPUT], onSearch: revealOnSearch("SOL") },
    { asset: "SOL" }
  );

  await internals.pickAsset();

  assert.ok(document.searchEvents.includes("input"), "no input event dispatched");
  assert.ok(document.searchEvents.includes("change"), "no change event dispatched");
});

test("an asset that search cannot reveal still reports asset_not_available", async () => {
  const { internals } = loadDeposit(
    { present: [SEL.SEARCH_INPUT, cell("BTC")] },
    { asset: "DOGE" }
  );

  await assert.rejects(() => internals.pickAsset(), (e) => {
    assert.match(e.message, /^asset_not_available:DOGE/);
    assert.match(e.message, /BTC/);
    return true;
  });
});

test("with no search box present, a visible asset is still picked", async () => {
  const { internals, document } = loadDeposit(
    { present: [cell("ETH")] },
    { asset: "ETH" }
  );

  await internals.pickAsset();

  assert.deepStrictEqual(document.clicks, [cell("ETH")]);
});
