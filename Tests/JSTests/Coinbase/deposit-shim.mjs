import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const SRC = fileURLToPath(
  new URL("../../../Sources/ZerohashSDK/Platforms/Coinbase/get-deposit-address.js", import.meta.url)
);
const SOURCE = readFileSync(SRC, "utf8");

const DOM_HELPERS = readFileSync(
  fileURLToPath(new URL("../../../Sources/ZerohashSDK/Automation/dom-helpers.js", import.meta.url)),
  "utf8"
);

class FakeEvent {
  constructor(type, init) {
    this.type = type;
    this.bubbles = !!(init && init.bubbles);
  }
}

class FakeHTMLInputElement {}
Object.defineProperty(FakeHTMLInputElement.prototype, "value", {
  configurable: true,
  get() { return this._value; },
  set(v) {
    this._value = v;
    if (typeof this._record === "function") this._record(v);
  }
});

const hostGlobals = () => ({
  setTimeout, clearTimeout, console,
  Event: FakeEvent,
  HTMLInputElement: FakeHTMLInputElement
});

/**
 * A mutable fake DOM. Elements are minted per query so identity never holds;
 * the search input is a stable singleton.
 *
 * @param {string[]} opts.present  selectors that match a visible element
 * @param {Function} opts.onSearch called with the typed value; mutate `present`
 *                                 to model Coinbase filtering the list
 */
const testidOf = (sel) => {
  const m = /^\[data-testid[\^$]?="(.*)"\]$/.exec(sel);
  return m ? m[1] : sel;
};

export function makeDocument({ present = [], onSearch = null } = {}) {
  const clicks = [];

  const element = (key) => ({
    selector: key,
    offsetParent: {},
    getBoundingClientRect: () => ({ width: 10, height: 10 }),
    getAttribute: (name) => (name === "data-testid" ? testidOf(key) : null),
    querySelector: () => null,
    querySelectorAll: () => [],
    closest: () => element(key + " (ancestor)"),
    click() { clicks.push(key); },
    focus() {},
    textContent: "",
    innerText: ""
  });

  const doc = {
    present: new Set(present),
    clicks,
    typed: [],
    searchEvents: [],
    body: element("body")
  };

  const searchInput = {
    ...element("SEARCH_INPUT"),
    tagName: "INPUT",
    _value: "",
    _record(v) {
      doc.typed.push(v);
      if (onSearch) onSearch(v, doc);
    },
    dispatchEvent(e) { doc.searchEvents.push(e.type); return true; }
  };

  doc.searchInput = searchInput;

  const SEARCH = () => SEL.SEARCH_INPUT;

  doc.querySelector = function (sel) {
    if (sel === SEARCH()) return this.present.has(sel) ? searchInput : null;
    return this.present.has(sel) ? element(sel) : null;
  };
  doc.querySelectorAll = function (sel) {
    if (sel === SEL.ANY_ASSET_CELL) {
      return [...this.present]
        .filter((s) => s.startsWith('[data-testid="ReceiveAssetSelectorCell-'))
        .map(element);
    }
    return this.present.has(sel) ? [element(sel)] : [];
  };

  return doc;
}

const WAIT_CAP_MS = 500;

function cappedPolls(document) {
  const $ = (sel) => document.querySelector(sel);
  const poll = (find, timeoutMs) =>
    new Promise((resolve) => {
      const end = Date.now() + Math.min(timeoutMs || WAIT_CAP_MS, WAIT_CAP_MS);
      (function tick() {
        const v = find();
        if (v) return resolve(v);
        if (Date.now() >= end) return resolve(null);
        setTimeout(tick, 15);
      })();
    });
  return {
    waitUntil: (find, timeoutMs) => poll(find, timeoutMs),
    waitFor: (sel, timeoutMs) =>
      poll(() => $(sel), timeoutMs).then((el) => {
        if (!el) throw new Error("element_not_found:" + sel);
        return el;
      })
  };
}

function run(document, params, idvReason) {
  const window = {
    HTMLInputElement: FakeHTMLInputElement,
    HTMLTextAreaElement: FakeHTMLInputElement
  };
  if (idvReason !== undefined) {
    window.__zhCoinbaseIdv = {
      blockedReasonForAction: async () => idvReason,
      blockedReasonFromVisibleDom: async () => idvReason,
      errorCodeForReason: (reason) =>
        reason === "idv_pending" ? "IDV_PENDING" : reason === "idv_failed" ? "IDV_FAILED" : null
    };
  }
  const ctx = vm.createContext({ window, document, params, ...hostGlobals() });
  vm.runInContext(DOM_HELPERS, ctx);
  Object.assign(window.__zhDom, cappedPolls(document));
  const started = vm.runInContext(SOURCE, ctx);
  if (started && typeof started.then === "function") started.then(() => {}, () => {});
  if (!window.__zhDeposit || !window.__zhDeposit.__internals) {
    throw new Error("deposit-shim: window.__zhDeposit.__internals is missing");
  }
  if (!window.__zhDeposit.__internals.SEL) {
    throw new Error("deposit-shim: __internals.SEL is missing — the harness harvests selectors from it");
  }
  return window;
}

const inertDocument = () => ({ querySelector: () => null, querySelectorAll: () => [] });

export const SEL = run(inertDocument(), { asset: "BTC" }).__zhDeposit.__internals.SEL;

/**
 * Runs get-deposit-address.js against a fresh mutable document. Tests drive
 * `__internals.pickAsset` directly, so the IIFE's own `run()` is left unawaited
 * and its rejection swallowed.
 */
export function loadDeposit(documentOptions = {}, params = {}, idvReason = undefined) {
  const document = makeDocument(documentOptions);
  const window = run(document, params, idvReason);
  return { internals: window.__zhDeposit.__internals, window, document };
}
