import assert from "node:assert";
import { test } from "node:test";
import { loadWithdraw } from "./withdraw-shim.mjs";

// previewRecipientMatches is pure (no DOM), so exercise it directly off __internals.
const { internals } = loadWithdraw();
const matches = internals.previewRecipientMatches;

const ADDR = "0x414eE036E1810cA5E0895f1045a07bb4d5268D5D";

test("passes when nothing comparable is on the preview", () => {
  // No preview text, or a plain contact name with no address token — never block.
  assert.equal(matches(null, ADDR), true);
  assert.equal(matches("", ADDR), true);
  assert.equal(matches("Sandro", ADDR), true);
});

test("passes when the full address is shown (case-insensitive)", () => {
  assert.equal(matches(ADDR, ADDR), true);
  assert.equal(matches("To " + ADDR.toLowerCase(), ADDR), true);
});

test("passes on a matching head…tail truncation (ellipsis or dots)", () => {
  assert.equal(matches("0x414eE0…268D5D", ADDR), true);
  assert.equal(matches("0x414eE0...268D5D", ADDR), true);
});

test("passes when a contact name is fused onto the truncated head", () => {
  // getInnerText normally separates name and address, but tolerate the fused form.
  assert.equal(matches("Sandro 0x414eE0…268D5D", ADDR), true);
});

test("fails on a mismatched tail (wrong address, real contradiction)", () => {
  assert.equal(matches("0x414eE0…AAAAAA", ADDR), false);
});

test("fails on a mismatched head with a coincidentally matching tail", () => {
  assert.equal(matches("0xDEAD00…268D5D", ADDR), false);
});
