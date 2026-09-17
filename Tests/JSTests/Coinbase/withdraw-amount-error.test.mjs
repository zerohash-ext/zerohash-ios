// classifyAmountError / readAmountValidationError. The phrases are
// English-only, and incomplete even in English. It now reports that it could not
// classify instead of asserting the generic bucket.
import { test } from "node:test";
import assert from "node:assert/strict";
import { loadWithdraw, SEL } from "./withdraw-shim.mjs";

function classify(msg) {
  return loadWithdraw().internals.classifyAmountError(msg);
}

function read({ error, balance }) {
  const texts = {};
  const present = [];
  if (error !== undefined) {
    present.push(SEL.AMOUNT_ERROR_MESSAGE);
    texts[SEL.AMOUNT_ERROR_MESSAGE] = error;
  }
  if (balance !== undefined) {
    present.push(SEL.ASSET_BALANCE);
    texts[SEL.ASSET_BALANCE] = balance;
  }
  return loadWithdraw({ present, texts }).internals.readAmountValidationError();
}

// ── English rejections must keep their existing classification ──────────────

test("the six English insufficient-funds patterns still classify", () => {
  // The SUBSTRINGS the classifier matches, not observed Coinbase copy. Kept because
  // removing them would regress en accounts.
  for (const msg of [
    "Add at least 0.001 BTC",
    "Insufficient balance",
    "Not enough BTC to cover this send",
    "This exceeds your balance",
    "That is more than your balance"
  ]) {
    assert.equal(classify(msg), "withdraw/insufficient-funds", msg);
  }
});

test("English below-minimum phrasing still classifies", () => {
  assert.equal(
    classify("The minimum amount you can send is 0.0001 BTC."),
    "withdraw/below-minimum"
  );
});

// ── The honest-ignorance contract ───────────────────────────────────────────

test("an unrecognised phrase classifies as nothing, rather than as the generic bucket", () => {
  // null is the whole point: the caller decides what to report, and can say
  // "unclassified" instead of implying a determination.
  assert.equal(classify("O valor é inválido"), null);
});

test("the real captured above-maximum rejection is not silently bucketed", () => {
  // A real above-maximum rejection. Before this change it returned
  // withdraw/amount-validation, indistinguishable from a genuine classification.
  assert.equal(classify("The maximum amount you can send is 10000000 USDC."), null);
});

test("a localized insufficient-funds message is not mistaken for a classification", () => {
  // "insuficiente" does not contain "insufficient" — the double f — so this was
  // never going to match, in any of Coinbase's 16 locales.
  assert.equal(classify("Saldo insuficiente"), null);
});

test("a localized below-minimum message is not mistaken for a classification", () => {
  // "mínimo" does not contain "minimum".
  assert.equal(classify("O valor mínimo que você pode enviar é 0,0001 BTC."), null);
});

// ── What the caller reports ─────────────────────────────────────────────────

test("a classified rejection reports its specific code and the message", () => {
  const out = read({ error: "Insufficient balance" });

  assert.match(out, /^withdraw\/insufficient-funds: Insufficient balance/);
  assert.doesNotMatch(out, /unclassified/);
});

test("an unclassified rejection says so, and still carries the venue's message", () => {
  const out = read({ error: "Saldo insuficiente" });

  assert.match(out, /^withdraw\/amount-validation:/, "the wire code must stay contract-stable");
  assert.match(out, /unclassified/, "and must admit it could not classify");
  assert.match(out, /Saldo insuficiente/, "the raw message is the only diagnostic left");
});

test("the balance is appended when Coinbase renders one", () => {
  const out = read({ error: "Insufficient balance", balance: "0.00001 BTC" });

  assert.match(out, /\(balance: 0\.00001 BTC\)/);
});

test("an empty error element reports that nothing surfaced", () => {
  const out = read({ error: "" });

  assert.match(out, /no error text surfaced/);
});

test("a localized trailing balance CTA is left in the message, not half-stripped", () => {
  // The old code stripped a trailing English "View balance" and nothing else.
  const out = read({ error: "Saldo insuficiente Ver saldo" });

  assert.match(out, /Ver saldo/);
});

test("the classifier no longer strips an English-only affordance", () => {
  const out = read({ error: "Insufficient balance View balance" });

  assert.match(out, /View balance/, "no locale-specific stripping should remain");
});
