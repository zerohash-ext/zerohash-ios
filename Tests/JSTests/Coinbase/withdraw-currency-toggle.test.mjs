// ensureCurrencyMode. Amounts go out asset-denominated while Coinbase
// opens the input in local fiat outside the US, so this toggle is on the critical
// path of every non-US send. It was found by aria-label, which reads "mudar".
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { loadWithdraw, SEL } from "./withdraw-shim.mjs";

const SOURCE = readFileSync(
  fileURLToPath(
    new URL("../../../Sources/ZerohashSDK/Platforms/Coinbase/withdraw.js", import.meta.url)
  ),
  "utf8"
);

const ICON = '[data-icon-name="arrowsVertical"]';
const ARIA_LABEL_TOGGLE = 'button[aria-label="switch"]';

/** A scoped amount-step root, modelling only what ensureCurrencyMode reads. */
function makeStep({ symbol, icons = 1, ariaLabel = false, flipsTo = null }) {
  const state = { symbol, clicked: [] };

  // Distinct identities so a test can assert WHICH element was clicked. The icon
  // is not the button: `closest("button")` is the walk under test.
  const button = { id: "toggle-button" };
  const icon = { id: "toggle-icon", closest: (sel) => (sel === "button" ? button : null) };
  const ariaButton = { id: "aria-label-button" };

  return {
    state,
    button,
    ariaButton,
    querySelector(sel) {
      if (sel === SEL.CURRENCY_SYMBOL) return { innerText: state.symbol };
      if (ariaLabel && sel === ARIA_LABEL_TOGGLE) return ariaButton;
      return null;
    },
    querySelectorAll(sel) {
      if (sel === ICON) return Array.from({ length: icons }, () => icon);
      return [];
    },
    // Injected as __zhDom.realisticClick, so it records the synthetic-event path
    // rather than a bare el.click().
    click(el) {
      state.clicked.push(el && el.id);
      if (flipsTo !== null) state.symbol = flipsTo;
    }
  };
}

function withStep(step) {
  const { internals } = loadWithdraw({}, { realisticClick: (el) => step.click(el) });
  return internals.ensureCurrencyMode;
}

test("switches a localized fiat input to asset mode via the icon, not the aria-label", async () => {
  // The pt-BR case that breaks today: the step carries the icon and NO English
  // aria-label, because Coinbase rendered it as "mudar".
  const step = makeStep({ symbol: "R$", flipsTo: "USDC" });
  const ensureCurrencyMode = withStep(step);

  const symbol = await ensureCurrencyMode(step, "asset", "USDC");

  assert.equal(symbol, "USDC");
  assert.deepEqual(step.state.clicked, ["toggle-button"]);
});

test("clicking the toggle goes through the synthetic-event path, not el.click()", async () => {
  // A bare toggle.click() would leave `clicked` empty — realisticClick is what this records.
  const step = makeStep({ symbol: "R$", flipsTo: "USDC" });
  const ensureCurrencyMode = withStep(step);

  await ensureCurrencyMode(step, "asset", "USDC");

  assert.deepEqual(step.state.clicked, ["toggle-button"]);
});

test("an English aria-label button alone is no longer enough to find the toggle", async () => {
  // This root used to SUCCEED, so it proves the aria-label path is gone.
  const step = makeStep({ symbol: "R$", icons: 0, ariaLabel: true, flipsTo: "USDC" });
  const ensureCurrencyMode = withStep(step);

  await assert.rejects(
    () => ensureCurrencyMode(step, "asset", "USDC"),
    /currency-toggle-not-found/
  );
  assert.deepEqual(step.state.clicked, []);
});

test("a missing toggle is reported as a missing toggle, not as a single-currency flow", async () => {
  // The old message blamed Coinbase for our own selector missing.
  const step = makeStep({ symbol: "R$", icons: 0 });
  const ensureCurrencyMode = withStep(step);

  await assert.rejects(() => ensureCurrencyMode(step, "asset", "USDC"), (e) => {
    assert.match(e.message, /currency-toggle-not-found/);
    assert.doesNotMatch(e.message, /only offers/);
    return true;
  });
});

test("two icons in scope is an error, never a first-match guess", async () => {
  // Document-wide there are two of these icons; the second drives the swap widget.
  const step = makeStep({ symbol: "R$", icons: 2, flipsTo: "USDC" });
  const ensureCurrencyMode = withStep(step);

  await assert.rejects(
    () => ensureCurrencyMode(step, "asset", "USDC"),
    /currency-toggle-ambiguous/
  );
  assert.deepEqual(step.state.clicked, []);
});

test("an input already in asset mode returns without clicking anything", async () => {
  // Pins the US path: symbol already matches the asset, so the toggle is never
  // consulted and behaviour is identical to before the change.
  const step = makeStep({ symbol: "USDC" });
  const ensureCurrencyMode = withStep(step);

  const symbol = await ensureCurrencyMode(step, "asset", "USDC");

  assert.equal(symbol, "USDC");
  assert.deepEqual(step.state.clicked, []);
});

test("an input already in fiat mode returns without clicking when fiat was asked for", async () => {
  // The negation arm of symbolMatchesRequest: "not the asset ticker" is how fiat
  // is recognised, so R$ satisfies a fiat request without a toggle.
  const step = makeStep({ symbol: "R$" });
  const ensureCurrencyMode = withStep(step);

  const symbol = await ensureCurrencyMode(step, "fiat", "USDC");

  assert.equal(symbol, "R$");
  assert.deepEqual(step.state.clicked, []);
});

test("a step with no currency symbol is reported as such", async () => {
  const step = makeStep({ symbol: "" });
  const ensureCurrencyMode = withStep(step);

  await assert.rejects(
    () => ensureCurrencyMode(step, "asset", "USDC"),
    /missing the currency symbol/
  );
});

test("the asset comparison is case-insensitive", async () => {
  const step = makeStep({ symbol: "usdc" });
  const ensureCurrencyMode = withStep(step);

  const symbol = await ensureCurrencyMode(step, "asset", "USDC");

  assert.equal(symbol, "usdc");
  assert.deepEqual(step.state.clicked, []);
});

test("withdraw.js no longer selects anything by aria-label", () => {
  // aria-label values are translated; data-icon-name values are not.
  assert.doesNotMatch(SOURCE, /aria-label="/);
});

test("withdraw.js does not use :has()", () => {
  // :has() needs Safari 15.4+, and it would also break the selection shim's selector engine.
  assert.doesNotMatch(SOURCE, /:has\(/);
});
