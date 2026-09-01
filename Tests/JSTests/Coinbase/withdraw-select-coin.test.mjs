import assert from "node:assert";
import { test } from "node:test";
import { loadSelection, el } from "./withdraw-selection-shim.mjs";

const coinCell = (ticker, opts = {}) => {
  const attrs = { "data-testid": `send-asset-selector-cell-${ticker}-cell-pressable` };
  if (opts.disabled) attrs.disabled = true;
  return el("button", attrs);
};

const searchBox = () => el("input", { "data-testid": "search-input" });

const assetStep = (...children) => {
  const step = el("div", { "data-testid": "step-assetSelection-active" });
  children.flat().forEach((c) => step.append(c));
  return step;
};

const advanceOnClick = (document, cell) => {
  cell.addEventListener("click", () => {
    const step = document.querySelector('[data-testid="step-assetSelection-active"]');
    if (step) step.attrs["data-testid"] = "step-assetSelection-inactive";
    document.body.append(el("div", { "data-testid": "step-l2SelectionStep-active" }));
  });
};

test("a ticker already rendered is clicked without touching the filter", async () => {
  const { internals, document } = loadSelection();
  const btc = coinCell("BTC");
  document.setContent(assetStep(searchBox(), btc));
  advanceOnClick(document, btc);

  await internals.selectCoin("BTC");

  const box = document.querySelector('[data-testid="search-input"]');
  assert.strictEqual(box.typed, undefined, "filter was used for an already-visible asset");
});

test("a held ticker below the fold is found by typing it into the filter", async () => {
  const box = searchBox();
  let document;
  const hooks = {
    onSearch: (value) => {
      if (String(value).toUpperCase() !== "SOL") return;
      const step = document.querySelector('[data-testid="step-assetSelection-active"]');
      if (!step || step.querySelector('[data-testid$="SOL-cell-pressable"]')) return;
      const sol = coinCell("SOL");
      step.append(sol);
      advanceOnClick(document, sol);
    }
  };
  const loaded = loadSelection(hooks);
  document = loaded.document;
  document.setContent(assetStep(box, coinCell("BTC")));

  await loaded.internals.selectCoin("SOL");

  assert.deepStrictEqual(box.typed, ["SOL"], "the ticker was not typed into the filter");
  assert.ok(box.events.includes("input"), "no input event — React would not re-render");
  assert.ok(box.events.includes("change"), "no change event — React would not re-render");
  assert.strictEqual(
    document.querySelector('[data-testid="step-assetSelection-active"]'),
    null,
    "the revealed cell was never clicked"
  );
});

test("a ticker the filter narrows down to a DISABLED cell is an incompatibility, not a not-found", async () => {
  let document;
  const hooks = {
    onSearch: (value) => {
      if (String(value).toUpperCase() !== "XRP") return;
      const step = document.querySelector('[data-testid="step-assetSelection-active"]');
      if (!step || step.querySelector('[data-testid$="XRP-cell-pressable"]')) return;
      step.append(coinCell("XRP", { disabled: true }));
    }
  };
  const loaded = loadSelection(hooks);
  document = loaded.document;
  document.setContent(assetStep(searchBox(), coinCell("BTC")));

  await assert.rejects(
    () => loaded.internals.selectCoin("XRP"),
    (e) => {
      assert.match(e.message, /withdraw\/address-unsupported/);
      assert.strictEqual(e.zhAddressUnsupported, true);
      return true;
    }
  );
});

test("with no filter box present, the enumerating not-found error is unchanged", async () => {
  const { internals, document } = loadSelection();
  document.setContent(assetStep(coinCell("BTC"), coinCell("ETH")));

  await assert.rejects(
    () => internals.selectCoin("DOGE"),
    (e) => {
      assert.match(e.message, /^withdraw\/coin-selection-required: DOGE/);
      assert.match(e.message, /BTC/);
      assert.match(e.message, /ETH/);
      return true;
    }
  );
});

test("a filter that cannot reveal the ticker still reports the enumerating not-found error", async () => {
  const { internals, document } = loadSelection();
  document.setContent(assetStep(searchBox(), coinCell("BTC")));

  await assert.rejects(
    () => internals.selectCoin("DOGE"),
    (e) => {
      assert.match(e.message, /^withdraw\/coin-selection-required: DOGE/);
      return true;
    }
  );
});
