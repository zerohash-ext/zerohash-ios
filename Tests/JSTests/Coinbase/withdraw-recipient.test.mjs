// Picking the recipient row out of Coinbase's address dropdown.
//
// The dropdown offers up to three kinds of row, and every one of them carries the
// FULL address in its data-testid. Transcribed from
// scrapping/bots/logs/coinbase_webkit/001/{98957de7,d9d96c27}:
//
//   favorite-<ADDRESS>-cell-pressable       starred contact, icon "star"
//   recent-send-<ADDRESS>-cell-pressable    previously sent to, icon "wallet"
//   recipient-manual-address-cell-pressable "use what I typed", no address in the id
//
// Matching on RENDERED TEXT cannot work. A favourited address renders the
// contact's name and a truncated address —
//   "Sandro Matheus Vila Nova Marques 9LFUw6...hZUGd2"
// — so the full string appears nowhere, and the old waitForExactText(address) hung
// until it threw. Worse, when the address is favourited Coinbase drops the manual
// row entirely, so there is no fallback that does render the full address.
import assert from "node:assert";
import { test } from "node:test";
import { loadWithdraw } from "./withdraw-shim.mjs";

// A real favourited Solana address from the captures, and a real recent one.
const FAV    = "9LFUw6mhsYEuuVDhJVkPbBZX1zn74KVACEqwMZhZUGd2";
const RECENT = "5ccL4u9E4m27YU19n5aAKgEDxNokB2qnCtwReRLm7Cqr";
const OTHER  = "7Ye9sLhgsrhDdrNj7sub6fBzazqXR6DJHEpHWfm5u7gE";

const favRow    = (a) => '[data-testid="favorite-' + a + '-cell-pressable"]';
const recentRow = (a) => '[data-testid="recent-send-' + a + '-cell-pressable"]';
const MANUAL    = '[data-testid="recipient-manual-address-cell-pressable"]';

const row = (present, address) =>
  loadWithdraw({ present }).internals.recipientRow(address);

// The reported bug: the chosen address is starred, so only the favourite row is
// offered and it never renders the full address.
test("a starred address is matched by its favourite row", () => {
  assert.ok(row([favRow(FAV)], FAV), "favourite row not matched");
});

test("a previously-used address is matched by its recent row", () => {
  assert.ok(row([recentRow(RECENT)], RECENT), "recent row not matched");
});

test("an address with no history falls back to the manual row", () => {
  assert.ok(row([MANUAL], OTHER), "manual row not matched");
});

// Both are the same address — the testid proves it — but the row keyed by the
// address is self-verifying, whereas the manual row's id says nothing about which
// value it will submit. Prefer the specific one.
test("an exact-address row is preferred over the manual row", () => {
  const picked = row([MANUAL, favRow(FAV)], FAV);
  assert.ok(picked);
  assert.strictEqual(picked.selector, favRow(FAV));
});

test("a recent row is preferred over the manual row", () => {
  const picked = row([MANUAL, recentRow(RECENT)], RECENT);
  assert.strictEqual(picked.selector, recentRow(RECENT));
});

// The dropdown lists other contacts too. Matching one of those would send someone
// else's money to the wrong place, so a row for a DIFFERENT address must never be
// selected — and with no manual row there is nothing safe to pick.
test("another contact's row is never selected for our address", () => {
  assert.strictEqual(row([favRow(OTHER), recentRow(RECENT)], FAV), null);
});

// With a wrong-address row AND a manual row, the manual row is the correct answer:
// it submits what we typed.
test("with only a foreign row and the manual row, the manual row wins", () => {
  const picked = row([favRow(OTHER), MANUAL], FAV);
  assert.strictEqual(picked.selector, MANUAL);
});

test("an empty dropdown yields nothing, so the caller keeps polling", () => {
  assert.strictEqual(row([], FAV), null);
});

// Addresses are case-sensitive on EVM chains and the testid preserves case. A
// case-mismatched favourite must not match; falling back to manual is correct.
test("a case-mismatched favourite does not match", () => {
  assert.strictEqual(row([favRow(FAV.toLowerCase())], FAV), null);
});
