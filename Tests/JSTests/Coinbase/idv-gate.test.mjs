import assert from "node:assert";
import { test } from "node:test";
import {
  loadGate,
  VERIFY_AUTHORIZATION,
  ATTEMPTS_REMAINING,
  BLOCKED_ON_IDV,
  BLOCKED_ON_IDV_AFTER_PRIOR_ATTEMPT,
  AUTHORIZATION_CLEARED,
  REGION_BLOCKED_ONLY,
  attemptsBody,
  httpError,
  cloudflareChallenge,
  networkFailure,
  neverResolves,
  TESTID_ENFORCER,
  TESTID_FIRST_RUN_PICKER,
  TESTID_ID_TYPE_PASSPORT,
  TESTID_GUIDANCE_CONTAINER,
  TESTID_RETRY_BUTTON,
  TESTID_IDENTITY_WRAPPER
} from "./idv-gate-shim.mjs";

test("a cleared authorization blocks nothing and costs one request", async () => {
  const { gate, calls } = loadGate({
    routes: { [VERIFY_AUTHORIZATION]: AUTHORIZATION_CLEARED }
  });

  assert.strictEqual(await gate.blockedReasonForAction("sends"), null);
  assert.strictEqual(calls.length, 1, "a healthy account must not pay for the attempt lookup");
});

test("a requirement we have not characterised is not relabelled as an identity problem", async () => {
  const { gate, breadcrumbs } = loadGate({
    routes: { [VERIFY_AUTHORIZATION]: REGION_BLOCKED_ONLY }
  });

  assert.strictEqual(await gate.blockedReasonForAction("sends"), null);
  assert.ok(breadcrumbs.some((b) => b.includes("other-requirement")));
});

test("the flow proceeds when the probe is unreadable", async () => {
  for (const [label, route] of [
    ["network failure", networkFailure],
    ["http error", () => httpError(500)],
    ["cloudflare challenge", cloudflareChallenge]
  ]) {
    const { gate } = loadGate({ routes: { [VERIFY_AUTHORIZATION]: route } });
    assert.strictEqual(
      await gate.blockedReasonForAction("sends"),
      null,
      `${label} must fail open`
    );
  }
});

test("a hanging probe aborts and fails open instead of stalling the flow", async () => {
  const { gate } = loadGate({ routes: { [VERIFY_AUTHORIZATION]: neverResolves } });

  const startedAt = Date.now();
  assert.strictEqual(await gate.blockedReasonForAction("sends"), null);
  assert.ok(Date.now() - startedAt < 8000);
});

test("the probe is shaped like Coinbase's own client request", async () => {
  const { gate, calls } = loadGate({
    routes: {
      [VERIFY_AUTHORIZATION]: BLOCKED_ON_IDV,
      [ATTEMPTS_REMAINING]: attemptsBody(0)
    }
  });

  await gate.blockedReasonForAction("receives");
  const probe = calls.find((c) => c.url.includes(VERIFY_AUTHORIZATION));

  assert.strictEqual(probe.method, "POST");
  assert.strictEqual(probe.credentials, "include");
  assert.deepStrictEqual(JSON.parse(probe.body), {
    action: "receives",
    df_pro_sealed_result: ""
  });
  assert.strictEqual(probe.headers["x-cb-platform"], "web");
  assert.strictEqual(probe.headers["content-type"], "application/json");
});

test("each flow asks about its own action", async () => {
  for (const action of ["sends", "receives"]) {
    const { gate, calls } = loadGate({
      routes: {
        [VERIFY_AUTHORIZATION]: BLOCKED_ON_IDV,
        [ATTEMPTS_REMAINING]: attemptsBody(0)
      }
    });
    await gate.blockedReasonForAction(action);
    const probe = calls.find((c) => c.url.includes(VERIFY_AUTHORIZATION));
    assert.strictEqual(JSON.parse(probe.body).action, action);
  }
});

test("no evidence of a prior attempt yields the pending reason", async () => {
  const { gate } = loadGate({
    routes: {
      [VERIFY_AUTHORIZATION]: BLOCKED_ON_IDV,
      [ATTEMPTS_REMAINING]: attemptsBody(0)
    }
  });

  assert.strictEqual(await gate.blockedReasonForAction("receives"), "idv_pending");
});

test("Coinbase's own guidance label is enough to name the failed state", async () => {
  const { gate, calls, breadcrumbs } = loadGate({
    routes: { [VERIFY_AUTHORIZATION]: BLOCKED_ON_IDV_AFTER_PRIOR_ATTEMPT }
  });

  assert.strictEqual(await gate.blockedReasonForAction("sends"), "idv_failed");
  assert.strictEqual(
    calls.length,
    1,
    "the label rides in the probe we already made, so it must cost no extra request"
  );
  assert.ok(breadcrumbs.some((b) => b.includes("block-label:prior-attempt")));
});

test("a positive attempt count also names the failed state", async () => {
  const { gate, breadcrumbs } = loadGate({
    routes: {
      [VERIFY_AUTHORIZATION]: BLOCKED_ON_IDV,
      [ATTEMPTS_REMAINING]: attemptsBody(2)
    }
  });

  assert.strictEqual(await gate.blockedReasonForAction("sends"), "idv_failed");
  assert.ok(breadcrumbs.some((b) => b.includes("attempts:prior-attempt")));
});

test("the retry screen also names the failed state", async () => {
  const { gate, breadcrumbs } = loadGate({
    routes: { [ATTEMPTS_REMAINING]: networkFailure },
    testids: [TESTID_ENFORCER, TESTID_GUIDANCE_CONTAINER, TESTID_RETRY_BUTTON]
  });

  assert.strictEqual(await gate.blockedReasonFromVisibleDom(), "idv_failed");
  assert.ok(breadcrumbs.some((b) => b.includes("screen:prior-attempt")));
});

test("an unreadable attempt count cannot turn a first-timer into a failure", async () => {
  for (const [label, route] of [
    ["network failure", networkFailure],
    ["http error", () => httpError(503)],
    ["malformed body", { data: { number_of_idv_attempts: "0" } }],
    ["empty body", {}]
  ]) {
    const { gate } = loadGate({
      routes: { [VERIFY_AUTHORIZATION]: BLOCKED_ON_IDV, [ATTEMPTS_REMAINING]: route }
    });
    assert.strictEqual(
      await gate.blockedReasonForAction("receives"),
      "idv_pending",
      `${label} must not be read as evidence of a prior attempt`
    );
  }
});

test("the first-run picker is not required to reach the pending reason", async () => {
  const { gate } = loadGate({
    routes: { [ATTEMPTS_REMAINING]: networkFailure },
    testids: [TESTID_ENFORCER, TESTID_FIRST_RUN_PICKER, TESTID_ID_TYPE_PASSPORT]
  });

  assert.strictEqual(await gate.blockedReasonFromVisibleDom(), "idv_pending");
});

test("the DOM fallback stays silent when no block anchor is on screen", async () => {
  const { gate } = loadGate({ routes: {}, testids: ["step-assetSelection-active"] });

  assert.strictEqual(await gate.blockedReasonFromVisibleDom(), null);
});

test("the preflight ignores the DOM when deciding whether to block", async () => {
  const { gate } = loadGate({
    routes: { [VERIFY_AUTHORIZATION]: AUTHORIZATION_CLEARED },
    testids: [TESTID_ENFORCER, TESTID_IDENTITY_WRAPPER, TESTID_RETRY_BUTTON]
  });

  assert.strictEqual(
    await gate.blockedReasonForAction("sends"),
    null,
    "block anchors on screen must not override a cleared authorization"
  );
});

test("every takeover anchor is enough on its own to detect the block", async () => {
  for (const testid of [
    TESTID_ENFORCER,
    "policy-restriction-enforcer-v3",
    TESTID_FIRST_RUN_PICKER,
    "onboarding_fs_loader",
    TESTID_IDENTITY_WRAPPER,
    TESTID_GUIDANCE_CONTAINER,
    "post-onboarding-navbar-actions"
  ]) {
    const { gate } = loadGate({
      routes: { [ATTEMPTS_REMAINING]: attemptsBody(0) },
      testids: [testid]
    });
    assert.ok(
      await gate.blockedReasonFromVisibleDom(),
      `${testid} must be recognised as the block`
    );
  }
});

test("each reason has exactly one error code for the deposit channel", async () => {
  const { gate } = loadGate();

  assert.strictEqual(gate.errorCodeForReason("idv_pending"), "IDV_PENDING");
  assert.strictEqual(gate.errorCodeForReason("idv_failed"), "IDV_FAILED");
  assert.strictEqual(gate.errorCodeForReason("something_else"), null);
});
