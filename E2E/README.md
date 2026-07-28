# Fund SDK e2e suite (gating) — AUTH-3839

XCUITest end-to-end coverage for the native iOS Fund SDK deposit/Auth flow,
against the **real gating backend** — no mocks anywhere in the path. iOS mirror
of Android's AUTH-3838 instrumentation suite and the AUTH-3630 web suite.
Follow-up to incident ENG-6631 (PIR ENG-6632, post-mortem AUTH-3622).

## What it covers

Two specs in `UITests/FundGatingE2ETests.swift`, each backed by its **own
gating platform** (the toggle is platform-level provisioning plus the JWT's
`auth_policy_enabled` claim):

| Spec                                                       | JWT                                      | Asserts                                                                                                     |
| ---------------------------------------------------------- | ---------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `testAuthEnabledJwtRendersIntegrationsSourcePicker`        | `auth_policy_enabled=true`               | Integrations source picker (`Select source`, or its `Deposit manually` escape hatch) renders; no SDK errors |
| `testNonAuthJwtBootsStraightToNativeFundFlow_eng6631Guard` | no claim (**the exact ENG-6631 config**) | Native Fund flow (`Select asset`) renders; no auth errors on boot; picker does NOT render                   |

## Architecture

XCUITest cannot run against a bare SPM library, so the suite uses a generated
host app:

```
E2E/
├── project.yml           # XcodeGen spec — generates ZerohashE2E.xcodeproj (gitignored)
├── HostApp/
│   └── HostApp.swift     # Minimal app: reads E2E_JWT from launch env, boots
│                         #   configureFund(.gating), mirrors SDK callbacks into
│                         #   accessibility labels (e2e-status / e2e-errors / e2e-closed)
└── UITests/
    ├── Gating.swift              # JWT mint from the gating kyc-mock-platform-server
    ├── FundSessionHarness.swift  # Launch + semantic-anchor helpers (waitForText, acceptTermsIfPresent)
    └── FundGatingE2ETests.swift  # The two specs
```

Flow per spec: mint a real JWT (`POST /manager/jwt` on
`kyc-mock-platform-server.gating.0hash.com` — auth platform mints with
`fwc` + `crypto-deposits`, non-auth with `fwc` only) → launch HostApp with
the JWT in `launchEnvironment` →
HostApp presents `ZerohashFundSession` on `Environment.gating`
(`connect-sdk.gating.0hash.com`) → assert on the same semantic anchors the
AUTH-3630 web page objects use.

`Environment.gating` is the only production-code change (internal-testing-only
enum case in `Sources/ZerohashSDK/ZerohashSDKTypes.swift`; `toWebValue` sends
`sandbox` — the web vocabulary only has production/sandbox, the gating
deployment's runtime env-config picks the hosts). Unit-covered in
`Tests/ZerohashSDKTests/EnvironmentTests.swift`.

## Credentials (required)

Gating **rejects the dev codes** (H552SV / ZHH1NA). You need **two** gating
platforms, one per config. No codes live in source:

| Config   | Provisioning                                                                       | Secrets / env vars                                              |
| -------- | ---------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| Auth     | `fwc` + `crypto-deposits` + `auth_policy_enabled` (integrations cbase/gemini/robinhood/gemini-fake) | `GATING_FUND_PLATFORM` / `GATING_FUND_PARTICIPANT`               |
| Non-auth | `fwc` only (the ENG-6631 config)                                                    | `GATING_FUND_NOAUTH_PLATFORM` / `GATING_FUND_NOAUTH_PARTICIPANT` |

- **CI**: all four as repo secrets (forwarded to the test runner as
  `TEST_RUNNER_`-prefixed env vars — xcodebuild strips the prefix and
  `Gating.requireCodes(authEnabled:)` reads the rest).
- **Local**: export the same four vars with the `TEST_RUNNER_` prefix (see below).

Ask #team-auth for provisioned gating codes.

## Running locally

```bash
# One-time
brew install xcodegen xcbeautify

# Generate the Xcode project (gitignored — regenerate after editing project.yml)
xcodegen generate --spec E2E/project.yml --project E2E

# Run the suite
TEST_RUNNER_GATING_FUND_PLATFORM=<auth_platform_code> \
TEST_RUNNER_GATING_FUND_PARTICIPANT=<auth_participant_code> \
TEST_RUNNER_GATING_FUND_NOAUTH_PLATFORM=<noauth_platform_code> \
TEST_RUNNER_GATING_FUND_NOAUTH_PARTICIPANT=<noauth_participant_code> \
xcodebuild test \
  -project E2E/ZerohashE2E.xcodeproj \
  -scheme FundGatingE2E \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

SDK unit tests (no credentials needed):

```bash
xcodebuild test -scheme ZerohashSDK \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## CI

`.github/workflows/fund-e2e-gating.yml`:

- **Triggers**: nightly (07:00 UTC), `workflow_dispatch`, and PRs touching
  `Sources/**` / `E2E/**` / the workflow itself.
- **Jobs**: `unit-tests` (SDK XCTest on simulator) → `fund-e2e-gating`
  (XcodeGen + XCUITest on an iPhone 16 simulator, macos-15 runner).
- **Artifacts**: the `.xcresult` bundle is uploaded on every run (14-day
  retention) — download and open in Xcode for screenshots + per-step logs.
- The mirror-sync workflow (`sync-to-zerohash-ext.yml`) filters
  `.github/workflows` from the public squash, so this workflow never reaches
  the public mirror.

## Triage

| Symptom                                                   | Likely cause                                                                                                                                                                                   |
| --------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Missing gating credentials` failure                      | One of the four `TEST_RUNNER_GATING_FUND_*` vars not set (or CI secrets missing) — both the auth and non-auth pairs are required                                                               |
| `mintJwt returned 4xx`                                    | Codes not valid on gating (dev codes are rejected) — re-provision via #team-auth                                                                                                               |
| Suite hangs, WebView blank, no errors recorded            | Gating deployment down — `curl -I https://connect-sdk.gating.0hash.com/mobile/index.html` should be 200                                                                                        |
| Bridge messages silently dropped (no callbacks ever fire) | `Environment.gating.trustedHosts` no longer matches the host the WebView loads — see `EnvironmentTests`                                                                                        |
| Picker renders on the non-Auth spec                       | **ENG-6631 regression** — the integrations gate is on for a JWT without `auth_policy_enabled`. Escalate, don't retry                                                                           |
| Flaky text-anchor waits                                   | Anchors are the AUTH-3630 web strings (`Select source`, `Select asset`, `Deposit manually`, `Accept`) — if the web copy changed, update `FundSessionHarness` and the web page objects together |

This is a **live-backend** suite: failures can be environmental (gating
deployment, credentials) rather than code regressions — triage against the
table above before assuming the SDK broke.
