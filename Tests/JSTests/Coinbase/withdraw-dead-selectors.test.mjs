// Handles that matched nothing, in any language. A selector that cannot match is
// worse than a missing one: it reads as coverage.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { SEL } from "./withdraw-shim.mjs";

const SOURCE = readFileSync(
  fileURLToPath(
    new URL("../../../Sources/ZerohashSDK/Platforms/Coinbase/withdraw.js", import.meta.url)
  ),
  "utf8"
);

const DOM_HELPERS = readFileSync(
  fileURLToPath(new URL("../../../Sources/ZerohashSDK/Automation/dom-helpers.js", import.meta.url)),
  "utf8"
);

/** Line comments stripped, so a guard never matches its own rationale. */
const code = (src) =>
  src
    .split("\n")
    .map((l) => l.replace(/\/\/.*$/, ""))
    .join("\n");

test("no selector is shipped for the step Coinbase never renders", () => {
  assert.equal(
    SEL.STEP_TRANSACTION_DETAILS,
    undefined,
    "STEP_TRANSACTION_DETAILS never matched a rendered step; it must not be on SEL"
  );
  assert.doesNotMatch(SOURCE, /transactionDetailsStep/);
});

test("the text matchers left without callers are gone, not parked", () => {
  // All orphaned by this branch; a text matcher kept "just in case" invites reuse.
  assert.doesNotMatch(code(DOM_HELPERS), /findButtonByText/);
  assert.doesNotMatch(code(SOURCE), /waitForButtonByText/);
  assert.doesNotMatch(code(SOURCE), /findButtonByTextSync/);
});

test("the port-scaffolding toolbox is gone", () => {
  // H was the only occurrence of itself in either repo — declared on port, never read.
  assert.doesNotMatch(code(SOURCE), /\bvar H\b/);
  assert.doesNotMatch(code(SOURCE), /\bH\./);
});

test("the helpers the toolbox listed are still here and still called", () => {
  // Guards against the deletion taking real code with it.
  const c = code(SOURCE);
  for (const fn of [
    "isVisible",
    "queryVisible",
    "waitForAny",
    "pollUntil",
    "waitForElement",
    "humanDelay",
    "humanClick",
    "setReactValue",
    "typeLikeHuman",
    "isDisabled",
    "getInnerText"
  ]) {
    assert.match(c, new RegExp(`\\b${fn}\\s*\\(`), `${fn} must survive`);
  }
});

test("the network-warning acknowledge carries no label constants", () => {
  // The acknowledge is resolved by its testid; its rendered label depends on the
  // account's language, so no list of texts may stand in for it.
  assert.equal(SEL.NETWORK_WARNING_ACK_TEXTS, undefined);
  assert.equal(SEL.NETWORK_WARNING_ACK_FRAGMENT, undefined);
  assert.doesNotMatch(SOURCE, /NETWORK_WARNING_ACK_(TEXTS|FRAGMENT)/);
  assert.match(code(SOURCE), /network-warning-step-understand/);
});

test("the prior-transfer detail carries no English label constants", () => {
  // The three labels were matched against rendered text, so they resolved on an
  // English account only. Deleted with the helper that read them.
  assert.equal(SEL.PENDING_AMOUNT_LABEL, undefined);
  assert.equal(SEL.PENDING_TO_LABEL, undefined);
  assert.equal(SEL.RISK_COMPLETE_BEFORE_LABEL, undefined);
  const c = code(SOURCE);
  assert.doesNotMatch(c, /PENDING_AMOUNT_LABEL|PENDING_TO_LABEL|RISK_COMPLETE_BEFORE_LABEL/);
  assert.doesNotMatch(c, /readLabeledValue/);
  assert.doesNotMatch(c, /Complete before/);
});

test("the blocking prior-transfer step is still found by its testid", () => {
  // The whole reason the labels were safe to delete.
  assert.equal(SEL.STEP_PREVIOUS_TRANSFER, '[data-testid="step-previousTransfer-active"]');
  assert.match(code(SOURCE), /SEL\.STEP_PREVIOUS_TRANSFER/);
});

test("the travel-rule step Coinbase does render is still reachable", () => {
  // Guards against over-deleting: transferDetailsStep is the real screen.
  assert.ok(SEL.TRANSFER_PURPOSE, "TRANSFER_PURPOSE must survive");
  assert.ok(SEL.TRANSFER_SUBMIT, "TRANSFER_SUBMIT must survive");
});
