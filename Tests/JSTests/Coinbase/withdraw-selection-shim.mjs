// Selection-phase test harness for withdraw.js.
//
// The other harness (withdraw-shim.mjs) models the document as a Set of matching
// SELECTOR STRINGS. That is a `selector -> boolean` oracle: it cannot express
// WHERE a node lives, and its stub `closest()` answers truthy for any selector.
// The network-acceptance-warning regression is precisely "an acknowledge button
// that is laid out but sits inside a container Coinbase already re-stamped
// `-inactive`", which is unrepresentable there.
//
// So this file ships a tiny real DOM instead — a parent-linked node tree with a
// selector engine covering exactly the shapes withdraw.js uses in the selection
// phase (tag, `[attr]`, `=`, `^=`, `$=`, `*=`, comma groups), plus `closest`,
// layout-driven visibility, and click listeners. Dependency-free (Node builtins
// only), matching the rest of Tests/JSTests. Fixtures mirror PR #89's step-dom.ts.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const SRC = fileURLToPath(
  new URL("../../../Sources/ZerohashSDK/Platforms/Coinbase/withdraw.js", import.meta.url)
);
const SOURCE = readFileSync(SRC, "utf8");

// ─── Minimal selector engine ─────────────────────────────────────────────

// Parse ONE comma-part into { tag, conds }. No descendant combinators are needed:
// withdraw.js's selection-phase selectors are each a single compound (an optional
// tag plus zero or more attribute conditions), OR-ed by commas at a higher level.
function parseCompound(part) {
  part = part.trim();
  let tag = null;
  const tagMatch = part.match(/^([a-zA-Z][a-zA-Z0-9]*)/);
  if (tagMatch) {
    tag = tagMatch[1].toLowerCase();
    part = part.slice(tagMatch[1].length);
  }
  const conds = [];
  const attrRe = /\[\s*([a-zA-Z_-]+)\s*(?:([~^$*]?=)\s*(?:"([^"]*)"|'([^']*)'))?\s*\]/g;
  let m;
  while ((m = attrRe.exec(part))) {
    const val = m[3] !== undefined ? m[3] : m[4] !== undefined ? m[4] : null;
    conds.push({ name: m[1], op: m[2] || null, val });
  }
  return { tag, conds };
}

function matchCompound(el, { tag, conds }) {
  if (tag && el.tag !== tag) return false;
  for (const c of conds) {
    const actual = el.getAttribute(c.name);
    if (actual === null) return false;
    if (c.op === null) continue; // presence only
    if (c.op === "=" && actual !== c.val) return false;
    if (c.op === "^=" && !actual.startsWith(c.val)) return false;
    if (c.op === "$=" && !actual.endsWith(c.val)) return false;
    if (c.op === "*=" && actual.indexOf(c.val) === -1) return false;
  }
  return true;
}

function matchSelector(el, selector) {
  return selector.split(",").some((part) => matchCompound(el, parseCompound(part)));
}

function queryAll(root, selector, firstOnly, out = []) {
  for (const child of root.children) {
    if (matchSelector(child, selector)) {
      out.push(child);
      if (firstOnly) return out;
    }
    queryAll(child, selector, firstOnly, out);
    if (firstOnly && out.length) return out;
  }
  return out;
}

// ─── Minimal element ─────────────────────────────────────────────────────

class El {
  constructor(tag, attrs = {}) {
    this.tag = String(tag).toLowerCase();
    this.attrs = { ...attrs };
    this.children = [];
    this.parent = null;
    this.hidden = false; // stands in for a display:none subtree
    this._text = "";
    this._listeners = {};
  }

  append(child) {
    child.parent = this;
    this.children.push(child);
    return child;
  }

  set textContent(v) {
    this._text = v;
    this.children = [];
  }
  get textContent() {
    if (this._text) return this._text;
    return this.children.map((c) => c.textContent).join("");
  }
  get innerText() {
    return this.textContent;
  }

  getAttribute(name) {
    const v = this.attrs[name];
    return v === undefined ? null : v;
  }
  get disabled() {
    return !!this.attrs.disabled;
  }
  get checked() {
    return !!this.attrs.checked;
  }

  // A node is "laid out" unless it or an ancestor is hidden — the only thing jsdom
  // (and here, this shim) has to fake, since isVisible keys off offsetParent + a
  // non-zero rect. A container re-stamped `-inactive` stays laid out on purpose:
  // that is exactly the stale-but-visible node the fix must skip via closest().
  get _hiddenChain() {
    let n = this;
    while (n) {
      if (n.hidden) return true;
      n = n.parent;
    }
    return false;
  }
  get offsetParent() {
    return this._hiddenChain ? null : this.parent || null;
  }
  getBoundingClientRect() {
    const laid = !this._hiddenChain;
    const w = laid ? 120 : 0;
    const h = laid ? 40 : 0;
    return { x: 0, y: 0, top: 0, left: 0, right: w, bottom: h, width: w, height: h };
  }

  matches(selector) {
    return matchSelector(this, selector);
  }
  closest(selector) {
    let n = this;
    while (n && n.matches) {
      if (n.matches(selector)) return n;
      n = n.parent;
    }
    return null;
  }
  querySelectorAll(selector) {
    return queryAll(this, selector, false);
  }
  querySelector(selector) {
    const r = queryAll(this, selector, true);
    return r.length ? r[0] : null;
  }

  addEventListener(type, fn) {
    (this._listeners[type] || (this._listeners[type] = [])).push(fn);
  }
  click() {
    (this._listeners.click || []).forEach((fn) => fn({ type: "click", target: this }));
  }
  focus() {}
}

// ─── Document ──────────────────────────────────────────────────────────────

class Doc {
  constructor() {
    this.html = new El("html");
    this.body = new El("body");
    this.html.append(this.body);
  }
  querySelectorAll(selector) {
    return queryAll(this.body, selector, false);
  }
  querySelector(selector) {
    const r = queryAll(this.body, selector, true);
    return r.length ? r[0] : null;
  }
  setContent(...nodes) {
    this.body.children = [];
    nodes.flat().forEach((n) => this.body.append(n));
  }
}

// ─── Fixtures (mirror PR #89's tests/.../step-dom.ts) ───────────────────────

export function el(tag, attrs, text) {
  const e = new El(tag, attrs || {});
  if (text != null) e.textContent = text;
  return e;
}

// The acknowledge button's real label, with the CURLY apostrophe (U+2019) Coinbase
// actually ships. Named so a spec can't accidentally assert the ASCII form.
export const ACK_LABEL = "Yes, it’s supported";

export const l2Step = (inner, state = "active") => {
  const step = el("div", { "data-testid": `step-l2SelectionStep-${state}` });
  [].concat(inner).forEach((c) => step.append(c));
  return step;
};

export const amountStep = () => {
  const step = el("div", { "data-testid": "step-amountEntry-active" });
  step.append(el("input", { "data-testid": "currency-input" }));
  return step;
};

export const currencyInput = () => el("input", { "data-testid": "currency-input" });

export const networkCell = (slug) =>
  el("button", { "data-testid": `l2-list-item-${slug}-cell-pressable` });

// The warning's own content: illustration, headline, the "don't show again"
// checkbox (present so a spec can assert we leave it alone) and the acknowledge
// button. `testid: false` models a Coinbase testid drift, leaving only the label.
export function warningBody(opts = {}) {
  const testid = opts.testid ?? true;
  const label = opts.label ?? ACK_LABEL;
  const nodes = [];
  nodes.push(el("img", { alt: "", src: "networkWarning-5.svg" }));
  nodes.push(el("h2", {}, "Does your recipient accept ETH on Base?"));
  const lbl = el("label", {});
  lbl.append(el("input", { type: "checkbox", "data-testid": "dont-show-again" }));
  lbl.append(el("span", {}, "Don’t show this warning for ETH on Base in the future"));
  nodes.push(lbl);
  const btnAttrs = { type: "button" };
  if (testid) btnAttrs["data-testid"] = "network-warning-step-understand";
  nodes.push(el("button", btnAttrs, label));
  return nodes;
}

// Simulate Coinbase advancing past the warning: the l2 container is re-stamped
// `-inactive` (its nodes stay mounted and laid out — the whole point) and the
// amount step mounts alongside it.
export function advanceToAmount(doc) {
  const l2 = doc.querySelector('[data-testid="step-l2SelectionStep-active"]');
  if (l2) l2.attrs["data-testid"] = "step-l2SelectionStep-inactive";
  doc.body.append(amountStep());
}

// ─── Loader ──────────────────────────────────────────────────────────────

const hostGlobals = (console) => ({ setTimeout, clearTimeout, console });

// realisticClick forwards to el.click() so fixtures' listeners fire; sleep is a
// short real delay so poll loops spin fast without busy-waiting. Date.now() (a VM
// intrinsic) drives the deadlines, so tests pass small timeouts.
function domStub() {
  return {
    sleep: () => new Promise((r) => setTimeout(r, 5)),
    waitFor: () => Promise.reject(new Error("selection-shim: waitFor is not stubbed")),
    realisticClick: (node) => {
      if (node && typeof node.click === "function") node.click();
    },
    findButtonByText: () => null
  };
}

/**
 * Runs withdraw.js against a fresh real-tree document.
 * @param {object} hooks { console } — override to capture console.warn.
 * @returns {{ internals, document, El }} document is a live Doc; mutate it and
 *          the running poll loops see the change.
 */
export function loadSelection(hooks = {}) {
  const document = new Doc();
  const window = { __zhDom: domStub() };
  vm.runInNewContext(SOURCE, { window, document, ...hostGlobals(hooks.console || console) });
  if (!window.__zhWithdraw || !window.__zhWithdraw.__internals) {
    throw new Error("selection-shim: window.__zhWithdraw.__internals is missing");
  }
  return { internals: window.__zhWithdraw.__internals, document, El };
}
