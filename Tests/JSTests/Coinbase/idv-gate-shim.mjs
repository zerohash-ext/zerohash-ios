import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const SRC = fileURLToPath(
  new URL("../../../Sources/ZerohashSDK/Platforms/Coinbase/coinbase-idv-gate.js", import.meta.url)
);
const SOURCE = readFileSync(SRC, "utf8");

export const VERIFY_AUTHORIZATION = "verify-authorization";
export const ATTEMPTS_REMAINING = "attempts-remaining";

export const BLOCKED_ON_IDV = {
  challenge_id: "44c0bd27-2b6f-4513-9537-42eb3aa63d98",
  status: "ACTION_AUTHORIZATION_STATUS_PENDING",
  next_steps: [
    { component_id: "COMPONENT_EXPERIENCE_BLOCKING_MESSAGE" },
    { component_id: "COMPONENT_EXPERIENCE_IDENTITY_DOCUMENT_VERIFICATION" }
  ]
};

export const BLOCKED_ON_IDV_AFTER_PRIOR_ATTEMPT = {
  challenge_id: "7c3f18aa-2b91-4e05-9d64-5a1d3c8e77b2",
  status: "ACTION_AUTHORIZATION_STATUS_PENDING",
  next_steps: [
    { component_id: "COMPONENT_EXPERIENCE_GUIDANCE_SCREEN" },
    { component_id: "COMPONENT_EXPERIENCE_IDENTITY_DOCUMENT_VERIFICATION" }
  ]
};

export const AUTHORIZATION_CLEARED = {
  challenge_id: "4a905a0a-cee4-4d0b-aea3-12687c98826d",
  status: "ACTION_AUTHORIZATION_STATUS_COMPLETE",
  next_steps: [],
  action_proof_token: "pt-v1-7c02a0cd"
};

export const REGION_BLOCKED_ONLY = {
  status: "ACTION_AUTHORIZATION_STATUS_PENDING",
  next_steps: [{ component_id: "COMPONENT_EXPERIENCE_BLOCKING_MESSAGE" }]
};

export const attemptsBody = (attempts) => ({
  data: {
    number_of_attempts_remaining: 6 - attempts,
    can_attempt_after_hours: 1,
    lifetime_max_reached: false,
    number_of_idv_attempts: attempts,
    bypass_retry_kyc: false
  }
});

export const TESTID_ENFORCER = "policy-restriction-enforcer-v2";
export const TESTID_FIRST_RUN_PICKER = "idv-guidance-select-id-type";
export const TESTID_ID_TYPE_PASSPORT = "id-capture-id-type-passport";
export const TESTID_GUIDANCE_CONTAINER = "onboarding-guidance-container";
export const TESTID_RETRY_BUTTON = "guid-action-btn-try-again";
export const TESTID_IDENTITY_WRAPPER = "identity-access-view-wrapper";

const matcherFor = (selector) => {
  const prefix = /^\[data-testid\^="(.*)"\]$/.exec(selector);
  if (prefix) return (id) => id.startsWith(prefix[1]);
  const exact = /^\[data-testid="(.*)"\]$/.exec(selector);
  if (exact) return (id) => id === exact[1];
  return () => false;
};

const jsonResponse = (body, { status = 200, headers = {} } = {}) => ({
  ok: status >= 200 && status < 300,
  status,
  headers: { get: (name) => headers[name] ?? null },
  text: async () => (typeof body === "string" ? body : JSON.stringify(body))
});

export const httpError = (status) => ({ __response: jsonResponse({}, { status }) });
export const cloudflareChallenge = () => ({
  __response: jsonResponse("<html>_cf_chl_opt</html>", { status: 200 })
});
export const networkFailure = () => ({ __throw: new Error("Failed to fetch") });
export const neverResolves = () => ({ __hang: true });

/**
 * Loads coinbase-idv-gate.js into a fresh vm context.
 *
 * @param {Object}   opts.routes  substring of the URL -> response descriptor
 * @param {string[]} opts.testids data-testids present in the fake document
 */
export function loadGate({ routes = {}, testids = [] } = {}) {
  const calls = [];
  const breadcrumbs = [];
  const present = new Set(testids);

  const document = {
    present,
    querySelector(selector) {
      const matches = matcherFor(selector);
      for (const id of this.present) {
        if (matches(id)) return { testid: id, selector };
      }
      return null;
    },
    querySelectorAll: () => []
  };

  const fetchImpl = (url, init) => {
    const headers = (init && init.headers) || {};
    calls.push({
      url,
      method: (init && init.method) || "GET",
      body: init && init.body,
      credentials: init && init.credentials,
      headers
    });
    const key = Object.keys(routes).find((k) => url.includes(k));
    if (key === undefined) return Promise.reject(new Error("unrouted fetch: " + url));
    const route = routes[key];
    const descriptor = typeof route === "function" ? route() : route;
    if (descriptor && descriptor.__throw) return Promise.reject(descriptor.__throw);
    if (descriptor && descriptor.__hang) {
      return new Promise((_resolve, reject) => {
        const signal = init && init.signal;
        if (signal) {
          signal.addEventListener("abort", () => {
            const err = new Error("aborted");
            err.name = "AbortError";
            reject(err);
          });
        }
      });
    }
    if (descriptor && descriptor.__response) return Promise.resolve(descriptor.__response);
    return Promise.resolve(jsonResponse(descriptor));
  };

  const window = {
    __zhTelemetry: {
      breadcrumb: (phase, note) => breadcrumbs.push(`${phase}:${note}`)
    }
  };

  const ctx = vm.createContext({
    window,
    document,
    fetch: fetchImpl,
    AbortController,
    setTimeout,
    clearTimeout,
    console
  });
  vm.runInContext(SOURCE, ctx);

  if (!window.__zhCoinbaseIdv) {
    throw new Error("idv-gate-shim: window.__zhCoinbaseIdv was not installed");
  }
  return { gate: window.__zhCoinbaseIdv, calls, breadcrumbs, document };
}
