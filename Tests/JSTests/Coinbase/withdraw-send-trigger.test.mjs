// Opening Coinbase's send modal, on a UI that localizes its own test IDs.
//
// Coinbase localizes `data-testid` AND `aria-label` on the bottom nav tabs and on
// the transfer drawer's items. On the pt-BR account in both exploration captures
// under scrapping/bots/logs/coinbase_webkit/001/{98957de7,d9d96c27}:
//
//   Transactions-Tab   -> 0 occurrences across 318 snapshots
//   Transações-Tab     -> 102 and 179 occurrences
//
// `data-icon-name` is NOT localized and is unique — max one occurrence per
// snapshot for each icon used here. It is the only stable handle.
//
//   Home -> home        Trading -> trading        Transactions -> invoice
//   Send crypto -> arrowUp   Receive -> arrowDown   Deposit -> bank
//
// These literals are transcribed from the captures on purpose. The fake document
// matches by exact string, so if a constant in withdraw.js drifts from a real
// capture value, these fail.
import assert from "node:assert";
import { test } from "node:test";
import { loadWithdraw } from "./withdraw-shim.mjs";

const QUICK_ACTION_SEND = '[data-testid="quick-action-send"]';
const TRANSFER_DROPDOWN = '[data-testid="transfer-dropdown-button"]';
const ICON_TRANSACTIONS = '[data-icon-name="invoice"]';
const ICON_SEND_CRYPTO  = '[data-icon-name="arrowUp"]';
const ICON_RECEIVE      = '[data-icon-name="arrowDown"]';

const trigger = (present) => loadWithdraw({ present }).internals.findSendTrigger();

// The reported failure: withdraw/send-trigger-not-found. The tab is right there,
// but under a localized test ID, so none of the four legacy triggers matched and
// the poll ran out its 15 s having clicked nothing.
test("the Transactions tab is found by icon even when its test ID is localized", () => {
  const t = trigger([ICON_TRANSACTIONS]);
  assert.ok(t, "no trigger found — the localized tab was missed");
  assert.strictEqual(t.advance, true);
});

// Second half of the same bug. The dispatch used to compare
// getAttribute("data-testid") against the literal "Transactions-Tab", so a
// localized tab would route to openSendModalStandard and look for a quick-action
// that is not there. Finding the tab is only half the fix; routing on it is the
// other half.
test("a localized tab routes to the Advance path, not the standard one", () => {
  assert.strictEqual(trigger([ICON_TRANSACTIONS]).advance, true);
});

test("the legacy quick-action still routes to the standard path", () => {
  const t = trigger([QUICK_ACTION_SEND]);
  assert.ok(t);
  assert.strictEqual(t.advance, false);
});

test("the transfer dropdown still routes to the Advance path", () => {
  const t = trigger([TRANSFER_DROPDOWN]);
  assert.ok(t);
  assert.strictEqual(t.advance, true);
});

// The quick-action is checked first, so a page offering both keeps the simpler
// route rather than detouring through the Transactions tab.
test("the quick-action wins when both it and the tab are present", () => {
  assert.strictEqual(trigger([QUICK_ACTION_SEND, ICON_TRANSACTIONS]).advance, false);
});

test("an empty page yields no trigger, so the caller keeps polling", () => {
  assert.strictEqual(trigger([]), null);
});

// The Home and Trading tabs carry icons too. Matching any nav icon would click the
// wrong tab, so only `invoice` may resolve.
test("the Home and Trading tabs are not mistaken for Transactions", () => {
  assert.strictEqual(trigger(['[data-icon-name="home"]']), null);
  assert.strictEqual(trigger(['[data-icon-name="trading"]']), null);
});

// The drawer's four items are localized in text — "Enviar criptomoeda",
// "Receber criptomoedas", "Depositar dinheiro", "Sacar dinheiro". The old code took
// the drawer's FIRST button, which is Send crypto only by ordering luck; Receive is
// one position away, and picking it would silently start the wrong flow.
test("the drawer's send-crypto item is chosen by icon, not by position", () => {
  const { internals } = loadWithdraw({ present: [ICON_RECEIVE, ICON_SEND_CRYPTO] });
  assert.ok(internals.sendCryptoDrawerItem(), "send-crypto item not resolved");
});

test("the drawer yields nothing when only the receive item is present", () => {
  const { internals } = loadWithdraw({ present: [ICON_RECEIVE] });
  assert.strictEqual(internals.sendCryptoDrawerItem(), null);
});
