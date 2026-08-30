// Coinbase withdraw — injected automation.
//
// Installs `window.__zhWithdraw = { start, continue, cancel }` (idempotent). The
// native side injects this file and then calls the relevant entry point; each
// returns a Promise of a WithdrawState-shaped object (or { cancelled } for
// cancel), awaited via callAsyncJavaScript on the SDK side.
(function () {
  if (window.__zhWithdraw) return; // idempotent across re-injection

  // ─── Selectors (Coinbase data-testids) ──────────────────────────────

  // Active step indicator.
  var STEP_ACTIVE = '[data-testid^="step-"][data-testid$="-active"]';

  // Send modal entry + recipient
  var SEND_URL = "https://www.coinbase.com/send";
  // Advance mobile: Transactions tab → global-actions CTA → BottomDrawer transfer

  // ── Locale-independent controls ──
  //
  // Coinbase localizes its own test IDs and aria-labels on the bottom nav tabs and
  // the transfer drawer. On a pt-BR account the Transactions tab is
  // `data-testid="Transações-Tab"`, so the old `[data-testid="Transactions-Tab"]`
  // matched nothing — 0 occurrences across 318 captured snapshots, against 102 and
  // 179 for the localized form. That is what produced withdraw/send-trigger-not-found.
  //
  // `data-icon-name` is NOT localized and is unique (max one per snapshot for each
  // of these), so it is the only stable handle. Match the icon, then walk up to the
  // control that owns it.
  var RECIPIENT_INPUT = '[data-testid="recipient-search-input"]';

  // Recipient dropdown rows. Every row carries the FULL address in its test id, so
  // match on that, never on rendered text: a starred address renders the contact's
  // name plus a TRUNCATED address ("Sandro … 9LFUw6...hZUGd2"), and when an address
  // is starred Coinbase drops the manual row entirely — so the full string appears
  // nowhere on the screen.
  var RECIPIENT_MANUAL_ADDRESS = '[data-testid="recipient-manual-address-cell-pressable"]';
  function favoriteRecipient(addr) {
    return '[data-testid="favorite-' + addr + '-cell-pressable"]';
  }
  function recentRecipient(addr) {
    return '[data-testid="recent-send-' + addr + '-cell-pressable"]';
  }

  // Conditional recipient-type chooser
  var STEP_SELECT_RECIPIENT_TYPE = '[data-testid="step-selectRecipientType-active"]';
  var SELF_CUSTODY_OPTION = '[data-testid="self-custody-option"]';
  var EXCHANGE_OPTION = '[data-testid="exchange-option"]';

  // Coin selection
  var COIN_LIST = '[data-testid^="send-asset-selector-cell-"][data-testid$="-cell-pressable"]';
  function coinDirect(ticker) {
    return '[data-testid="send-asset-selector-cell-' + String(ticker).toUpperCase() + '-cell-pressable"]';
  }

  // Network selection
  var NETWORK_ITEMS = '[data-testid$="-cell-pressable"][data-testid^="l2-list-item-"]:not([disabled])';
  var NETWORK_ITEMS_ANY = '[data-testid$="-cell-pressable"][data-testid^="l2-list-item-"]';
  function networkTestId(slug) {
    return '[data-testid="l2-list-item-' + String(slug).toLowerCase() + '-cell-pressable"]';
  }

  // Network-acceptance warning
  var NETWORK_WARNING_CONTINUE = '[data-testid="network-warning-step-understand"]';

  // Coinbase's Transitioner keeps the OUTGOING step mounted while it fades out,
  // re-stamped `-inactive`. isVisible (below) only checks offsetParent + a
  // non-zero rect — never opacity — so a fading node still reads as visible.
  // Anything inside one of these containers is STALE and must not drive the flow:
  // reading a just-acknowledged warning out of one is what produced
  // `withdraw/selection-phase-stalled: revisited networkWarning`.
  var STEP_INACTIVE = '[data-testid^="step-"][data-testid$="-inactive"]';
  // The container hosting BOTH the network list and the acceptance warning — the
  // scope root for the label fallback below.
  var STEP_L2_SELECTION = '[data-testid="step-l2SelectionStep-active"]';
  // Label fallbacks for the acknowledge button, used only once a testid drift has
  // hidden NETWORK_WARNING_CONTINUE. Coinbase renders a CURLY apostrophe (U+2019);
  // the ASCII form and an apostrophe-free fragment follow as last resorts.
  var NETWORK_WARNING_ACK_TEXTS = ["Yes, it’s supported", "Yes, it's supported"];
  var NETWORK_WARNING_ACK_FRAGMENT = "supported";

  // Destination tag / memo
  var STEP_DESTINATION_TAG = '[data-testid="step-destinationTagStep-active"]';
  var DESTINATION_TAG_INPUT = STEP_DESTINATION_TAG + ' input';
  var SKIP_DESTINATION_TAG = '[data-testid="skip-destination-tag"]';

  // Risk-engine ID/liveness verification (current send).
  //
  // STEP_RISK_VERIFICATION is the container; it holds nested sub-steps. Only the
  // sub-states below mean the screen has settled — the container can be up while
  // Coinbase is still rendering into it. Matched by data-testid, never by button
  // text: the captured account renders these in Portuguese.
  var STEP_RISK_VERIFICATION = '[data-testid="step-riskSelfServeStep-active"]';
  var RISK_START_CHALLENGE = '[data-testid="start-challenge-button"]';
  var RISK_STEP_IDV = '[data-testid="step-idVerification-active"]';
  var RISK_IDV_FAILED = '[data-testid="id-capture-reskinned-failure-view"]';
  // Transient intro frame, rendered before the buttons exist.
  var RISK_SCAM_INTRO = '[data-testid="scam-warning-intro"]';
  // Only used by readPendingTransfer, for the separate step-previousTransfer
  // screen. The risk screen has no such label.
  var RISK_COMPLETE_BEFORE_LABEL = "Complete before";

  // "Review pending transfer" — a PRIOR transfer blocking a new send
  var STEP_PREVIOUS_TRANSFER = '[data-testid="step-previousTransfer-active"]';
  var PENDING_AMOUNT_LABEL = "Amount";
  var PENDING_TO_LABEL = "To";

  var STEP_WBL_HOLD = '[data-testid="step-wblHoldStep-active"]';

  // Terminal "Transfer canceled" screen
  var STEP_USER_CANCELLATION = '[data-testid="step-userCancellationSuccess-active"]';

  // Amount entry
  var CURRENCY_INPUT = '[data-testid="currency-input"]';
  var MAX_BUTTON = '[data-testid="max-button"]';
  var PREVIEW_SEND = '[data-testid="preview-send-button"]';
  var ASSET_BALANCE = '[data-testid="asset-balance-cell"]';

  // Travel rule (FATF) form — Coinbase's `recipientInfoStep` ("Who are you
  // sending to?"). Carries beneficiary name, a country select, a BR CPF/tax-id
  // field, and the self-transfer checkbox.
  var BENEFICIARY_NAME = '[data-testid="beneficiary-full-name"]';
  var COUNTRY_SELECT = '[data-testid="country-select"]';
  function countryOption(cc) { return '[data-testid="country-option-' + cc + '"]'; }
  var SUBMIT_BUTTON = '[data-testid="submit-button"]';
  // "I'm transferring to myself" checkbox. The real <input type=checkbox> is
  // visually hidden behind a styled wrapper; `own-account-checkbox-parent` is the
  // hittable element. Ticking it collapses (auto-fills) the name + CPF fields.
  var OWN_ACCOUNT_CHECKBOX = '[data-testid="own-account-checkbox"]';
  var OWN_ACCOUNT_CHECKBOX_PARENT = '[data-testid="own-account-checkbox-parent"]';

  // Transfer details (purpose + relationship) form
  var TRANSFER_PURPOSE = '[data-testid="transfer-purpose-select"]';
  var TRANSFER_RELATIONSHIP = '[data-testid="relationship-with-beneficiary-select"]';
  var TRANSFER_SUBMIT = '[data-testid="transfer-details-step-submit-container"] button';
  var DROPDOWN_OPTION_SELECTORS = ['[role="option"]', '[role="menuitem"]', '[data-testid*="option"]'];

  // Preview + confirm
  var SEND_NOW = '[data-testid="send-now-button"]';
  var SEND_PREVIEW_FIAT = '[data-testid="send-preview-fiat-header"]';
  var SEND_PREVIEW_CRYPTO = '[data-testid="send-preview-crypto-header"]';
  var SEND_PREVIEW_RECIPIENT = '[data-testid="send-preview-recipient-container"]';
  var SEND_PREVIEW_NETWORK = '[data-testid="send-preview-network"]';
  var SEND_PREVIEW_TIME = '[data-testid="time-estimate"]';
  var SEND_PREVIEW_FEE = '[data-testid="send-preview-footer-network-fee-explainer"]';
  var AMOUNT_ERROR_MESSAGE = '[data-testid="error-message"]';

  // 2FA / loading / success
  //
  // IDENTITY_ACCESS_WRAPPER mounts EMPTY, inside VERIFY_ACCESS_LOADER, ~1.4s
  // BEFORE Coinbase's commit request resolves. It is not evidence of anything on
  // its own — see probePostConfirm.
  var IDENTITY_ACCESS_WRAPPER = '[data-testid="identity-access-view-wrapper"]';
  var VERIFY_ACCESS_LOADER = '[data-testid="verify_access_loader"]';
  var STATUS_LOADING = '[data-testid="status-animation-loading"]';
  var STATUS_ANIMATION_SUCCESS = '[data-testid="status-animation-success"]';
  var TWO_FACTOR_TOTP = '[data-testid="two-factor-button-TOTP"]';
  var TWO_FACTOR_SMS = '[data-testid="two-factor-button-SMS"]';
  var PASSKEY_PROMPT = '[data-testid="passkey-auth"], [data-testid="passkey-verify-button"]';
  var OTP_INPUT = "#one-time-code";
  var OTP_CONTAINER = '[data-testid="code-inputs-container"]';
  var SEND_SUCCESS = '[data-testid="send-success-content"]';
  var SUCCESS_HEADLINE = '[data-testid="send-success-content-headline"]';
  var STATUS_COMPLETE_BTN = '[data-testid="status-step-complete-button"]';
  var MODAL_OVERLAY = '[data-testid="modal-overlay"]';

  // Post-send transaction-details step
  var STEP_TRANSACTION_DETAILS = '[data-testid="step-transactionDetailsStep-active"]';

  // Keep references so the scaffold's selector set isn't dead-code-eliminated and
  // is available to the driver functions ported in later steps.
  var SEL = {
    STEP_ACTIVE: STEP_ACTIVE,
    RECIPIENT_INPUT: RECIPIENT_INPUT,
    RECIPIENT_MANUAL_ADDRESS: RECIPIENT_MANUAL_ADDRESS,
    favoriteRecipient: favoriteRecipient,
    recentRecipient: recentRecipient,
    STEP_SELECT_RECIPIENT_TYPE: STEP_SELECT_RECIPIENT_TYPE,
    SELF_CUSTODY_OPTION: SELF_CUSTODY_OPTION,
    EXCHANGE_OPTION: EXCHANGE_OPTION,
    COIN_LIST: COIN_LIST,
    coinDirect: coinDirect,
    NETWORK_ITEMS: NETWORK_ITEMS,
    NETWORK_ITEMS_ANY: NETWORK_ITEMS_ANY,
    networkTestId: networkTestId,
    NETWORK_WARNING_CONTINUE: NETWORK_WARNING_CONTINUE,
    STEP_INACTIVE: STEP_INACTIVE,
    STEP_L2_SELECTION: STEP_L2_SELECTION,
    NETWORK_WARNING_ACK_TEXTS: NETWORK_WARNING_ACK_TEXTS,
    NETWORK_WARNING_ACK_FRAGMENT: NETWORK_WARNING_ACK_FRAGMENT,
    STEP_DESTINATION_TAG: STEP_DESTINATION_TAG,
    DESTINATION_TAG_INPUT: DESTINATION_TAG_INPUT,
    SKIP_DESTINATION_TAG: SKIP_DESTINATION_TAG,
    STEP_RISK_VERIFICATION: STEP_RISK_VERIFICATION,
    RISK_START_CHALLENGE: RISK_START_CHALLENGE,
    RISK_STEP_IDV: RISK_STEP_IDV,
    RISK_IDV_FAILED: RISK_IDV_FAILED,
    RISK_SCAM_INTRO: RISK_SCAM_INTRO,
    RISK_COMPLETE_BEFORE_LABEL: RISK_COMPLETE_BEFORE_LABEL,
    STEP_PREVIOUS_TRANSFER: STEP_PREVIOUS_TRANSFER,
    PENDING_AMOUNT_LABEL: PENDING_AMOUNT_LABEL,
    PENDING_TO_LABEL: PENDING_TO_LABEL,
    STEP_WBL_HOLD: STEP_WBL_HOLD,
    STEP_USER_CANCELLATION: STEP_USER_CANCELLATION,
    CURRENCY_INPUT: CURRENCY_INPUT,
    MAX_BUTTON: MAX_BUTTON,
    PREVIEW_SEND: PREVIEW_SEND,
    ASSET_BALANCE: ASSET_BALANCE,
    BENEFICIARY_NAME: BENEFICIARY_NAME,
    COUNTRY_SELECT: COUNTRY_SELECT,
    countryOption: countryOption,
    SUBMIT_BUTTON: SUBMIT_BUTTON,
    OWN_ACCOUNT_CHECKBOX: OWN_ACCOUNT_CHECKBOX,
    OWN_ACCOUNT_CHECKBOX_PARENT: OWN_ACCOUNT_CHECKBOX_PARENT,
    TRANSFER_PURPOSE: TRANSFER_PURPOSE,
    TRANSFER_RELATIONSHIP: TRANSFER_RELATIONSHIP,
    TRANSFER_SUBMIT: TRANSFER_SUBMIT,
    DROPDOWN_OPTION_SELECTORS: DROPDOWN_OPTION_SELECTORS,
    SEND_NOW: SEND_NOW,
    SEND_PREVIEW_FIAT: SEND_PREVIEW_FIAT,
    SEND_PREVIEW_CRYPTO: SEND_PREVIEW_CRYPTO,
    SEND_PREVIEW_RECIPIENT: SEND_PREVIEW_RECIPIENT,
    SEND_PREVIEW_NETWORK: SEND_PREVIEW_NETWORK,
    SEND_PREVIEW_TIME: SEND_PREVIEW_TIME,
    SEND_PREVIEW_FEE: SEND_PREVIEW_FEE,
    AMOUNT_ERROR_MESSAGE: AMOUNT_ERROR_MESSAGE,
    IDENTITY_ACCESS_WRAPPER: IDENTITY_ACCESS_WRAPPER,
    VERIFY_ACCESS_LOADER: VERIFY_ACCESS_LOADER,
    STATUS_LOADING: STATUS_LOADING,
    STATUS_ANIMATION_SUCCESS: STATUS_ANIMATION_SUCCESS,
    TWO_FACTOR_TOTP: TWO_FACTOR_TOTP,
    TWO_FACTOR_SMS: TWO_FACTOR_SMS,
    PASSKEY_PROMPT: PASSKEY_PROMPT,
    OTP_INPUT: OTP_INPUT,
    OTP_CONTAINER: OTP_CONTAINER,
    SEND_SUCCESS: SEND_SUCCESS,
    SUCCESS_HEADLINE: SUCCESS_HEADLINE,
    STATUS_COMPLETE_BTN: STATUS_COMPLETE_BTN,
    MODAL_OVERLAY: MODAL_OVERLAY,
    STEP_TRANSACTION_DETAILS: STEP_TRANSACTION_DETAILS
  };

  // ─── Withdraw-local DOM/input helpers ───────────────────────────────
  //
  // Build on the SDK's shared window.__zhDom (injected before this file). Kept
  // withdraw-local so the shared dom-helpers.js (used by deposit/balance) is
  // untouched; promote to shared later if another platform needs them.
  var D = window.__zhDom;

  // Framework-telemetry breadcrumb. No-op unless the native install prelude ran
  // for this dispatch (i.e. telemetry is on); never carries PII.
  function bc(phase, note) { if (window.__zhTelemetry) window.__zhTelemetry.breadcrumb(phase, note); }

  function isVisible(el) {
    if (!el) return false;
    if (el.offsetParent !== null) return true;
    var r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0;
  }

  // First VISIBLE element matching `sel`, or null.
  function queryVisible(sel) {
    var nodes = document.querySelectorAll(sel);
    for (var i = 0; i < nodes.length; i++) {
      if (isVisible(nodes[i])) return nodes[i];
    }
    return null;
  }

  // queryVisible scoped to LIVE content: same visibility test, but skips nodes
  // sitting inside a step container Coinbase already re-stamped `-inactive`.
  // isVisible can't tell a fading container from a live one (it never looks at
  // opacity), which is how a just-acknowledged warning got re-read as fresh.
  function queryVisibleLive(sel) {
    var nodes = document.querySelectorAll(sel);
    for (var i = 0; i < nodes.length; i++) {
      if (!isVisible(nodes[i])) continue;
      if (nodes[i].closest(SEL.STEP_INACTIVE)) continue;
      return nodes[i];
    }
    return null;
  }

  // Poll until any selector matches a visible element; resolve the matched
  // SELECTOR STRING (so callers can branch on `which === SEL.X`), null on timeout.
  function waitForAny(selectors, timeoutMs) {
    timeoutMs = timeoutMs || 15000;
    var end = Date.now() + timeoutMs;
    return new Promise(function (resolve) {
      (function poll() {
        for (var i = 0; i < selectors.length; i++) {
          if (queryVisible(selectors[i])) return resolve(selectors[i]);
        }
        if (Date.now() >= end) return resolve(null);
        setTimeout(poll, 150);
      })();
    });
  }

  // Poll `fn` until it returns truthy; reject with `errMsg` on timeout.
  function pollUntil(fn, timeoutMs, errMsg) {
    timeoutMs = timeoutMs || 15000;
    var end = Date.now() + timeoutMs;
    return new Promise(function (resolve, reject) {
      (function poll() {
        var v;
        try { v = fn(); } catch (e) { v = null; }
        if (v) return resolve(v);
        if (Date.now() >= end) return reject(new Error(errMsg || "pollUntil timed out"));
        setTimeout(poll, 150);
      })();
    });
  }

  // Resolve the element for `sel` or reject on timeout (delegates to __zhDom).
  function waitForElement(sel, timeoutMs) {
    return D.waitFor(sel, timeoutMs);
  }

  // Poll for a button/clickable whose text matches `text` (exact or contains).
  function waitForButtonByText(text, opts) {
    opts = opts || {};
    var root = opts.root || document;
    var match = opts.match || "exact";
    var requireEnabled = opts.requireEnabled || false;
    var timeoutMs = opts.timeoutMs || 5000;
    var want = String(text).toLowerCase();
    return pollUntil(function () {
      var btns = root.querySelectorAll("button, [role='button'], a");
      for (var i = 0; i < btns.length; i++) {
        var t = (btns[i].textContent || "").trim().toLowerCase();
        var textMatch = match === "contains" ? t.indexOf(want) !== -1 : t === want;
        // requireEnabled: keep waiting while the matched button is disabled
        // (Coinbase disables Continue until async field validation settles).
        if (textMatch && !(requireEnabled && isDisabled(btns[i]))) return btns[i];
      }
      return null;
    }, timeoutMs, "withdraw/button-not-found: " + text);
  }

  function humanDelay(ms) { return D.sleep(ms || 0); }
  function humanClick(el) { D.realisticClick(el); return D.sleep(50); }

  var setReactValue = D.setReactValue;

  function typeLikeHuman(input, text) {
    input.focus();
    setReactValue(input, String(text));
    return D.sleep(50);
  }

  function isDisabled(el) {
    return !!(el && (el.disabled || el.getAttribute("aria-disabled") === "true"));
  }

  function getInnerText(el) {
    return el ? (el.innerText || el.textContent || "") : "";
  }

  // Toolbox the driver functions (ported in later sub-steps) build on.
  var H = {
    isVisible: isVisible, queryVisible: queryVisible, waitForAny: waitForAny,
    pollUntil: pollUntil, waitForElement: waitForElement, waitForButtonByText: waitForButtonByText,
    humanDelay: humanDelay, humanClick: humanClick, setReactValue: setReactValue,
    typeLikeHuman: typeLikeHuman, isDisabled: isDisabled, getInnerText: getInnerText
  };

  // ─── Screen drivers ──────────────────────────────────────────────────

  // Coinbase emits a `loaded` wrapper around real steps during transitions;
  // walk in reverse so the innermost (deepest) real step wins over it.
  function readActiveStep() {
    var all = document.querySelectorAll(SEL.STEP_ACTIVE);
    for (var i = all.length - 1; i >= 0; i--) {
      var id = all[i].getAttribute("data-testid") || "";
      var m = id.match(/^step-(.+)-active$/);
      if (m && m[1] !== "loaded") return m[1];
    }
    if (all.length > 0) return "loaded";
    return null;
  }

  // Desktop shows a direct "Send" quick-action; mobile collapses it into a
  // "Transfer" dropdown; Coinbase Advance uses a two-click dropdown. Detect
  // which UI is active, then click through to the recipient field.
  // First VISIBLE control owning an icon named `iconName`, or null. Used where
  // Coinbase localizes the test ID and the icon is the only stable handle.


  function probeSendEntry() {
    return {
      recipient: !!document.querySelector(SEL.RECIPIENT_INPUT),
      previousTransfer: !!queryVisible(SEL.STEP_PREVIOUS_TRANSFER),
      holdModal: isHoldModalPresent()
    };
  }

  // Precedence mirrors awaitRecipientOrPendingBlock, which this replaces at the
  // entry point: recipient first, then the blockers. null means "nothing yet" and
  // keeps pollUntil waiting.
  function classifySendEntry(p) {
    if (p.recipient) return { entry: "deep-link" };
    if (p.previousTransfer) return { entry: "pending-transfer" };
    if (p.holdModal) return { entry: "funds-not-available" };
    return null;
  }

  // The session loads /send, which mounts the recipient step directly. The
  // dashboard click-through is gone rather than kept as a fallback: it existed only
  // to reach this step from /home, and a Coinbase change that stops /send mounting
  // would otherwise route silently back onto it. That path is the flaky one — the
  // send CTA was present in 33 of 38 snapshots in one capture and 0 of 8 in another
  // — so the fallback would hide the regression it was meant to survive.
  //
  // This fails loudly instead, naming the URL and the selector it waited for.
  async function openSendModal() {
    var entry = await pollUntil(function () {
      return classifySendEntry(probeSendEntry());
    }, 15000, "withdraw/send-step-not-mounted: " + SEND_URL + " " + SEL.RECIPIENT_INPUT);
    bc("send-entry", entry.entry);
    if (entry.entry === "pending-transfer") throw pendingTransferError(readPendingTransfer());
    if (entry.entry === "funds-not-available") throw fundsNotAvailableError();
  }

  // Tagged error carrying a blocking prior transfer's details. Thrown from
  // awaitRecipientOrPendingBlock and converted to a rejected/pending_transfer
  // state by `start`'s catch.
  function pendingTransferError(details) {
    var e = new Error("withdraw/pending-transfer: a prior transfer needs verification before sending again");
    e.zhPendingTransfer = details;
    return e;
  }

  // Read the prior transfer's Amount / To / Complete-before from the visible
  // "Review pending transfer" screen. All-null when the step isn't up.
  function readPendingTransfer() {
    var step = queryVisible(SEL.STEP_PREVIOUS_TRANSFER);
    if (!step) return { amount: null, recipient: null, completeBefore: null };
    return {
      amount: readLabeledValue(step, SEL.PENDING_AMOUNT_LABEL),
      recipient: readLabeledValue(step, SEL.PENDING_TO_LABEL),
      completeBefore: readLabeledValue(step, SEL.RISK_COMPLETE_BEFORE_LABEL)
    };
  }

  function fundsNotAvailableError() {
    var e = new Error("withdraw/funds-not-available: Coinbase is blocking sends (balance on temporary hold)");
    e.zhFundsNotAvailable = true;
    return e;
  }

  function isHoldModalPresent() {
    return !!queryVisible(SEL.STEP_WBL_HOLD);
  }

  // After the send trigger Coinbase normally shows the recipient field — unless a
  // prior transfer is still pending identity verification, in which case it shows
  // the blocking "Review pending transfer" screen instead. Race the two so we
  // recognize the block immediately rather than timing out on the missing
  // recipient input; on the block, throw with the prior transfer's details.
  async function awaitRecipientOrPendingBlock() {
    // Match the recipient by DOM PRESENCE (querySelector), mirroring the original
    // waitForElement wait — it can mount before our isVisible heuristic considers
    // it visible, so a visibility-gated race would spuriously time out. The block
    // screen is the active step when up, so detect it by visibility.
    var deadline = Date.now() + 15000;
    for (;;) {
      if (document.querySelector(SEL.RECIPIENT_INPUT)) return;
      if (queryVisible(SEL.STEP_PREVIOUS_TRANSFER)) throw pendingTransferError(readPendingTransfer());
      if (isHoldModalPresent()) throw fundsNotAvailableError();
      if (Date.now() >= deadline) throw new Error("withdraw/recipient-not-found: " + SEL.RECIPIENT_INPUT);
      await D.sleep(150);
    }
  }

  // The dropdown row that submits `address`, or null while none is offered.
  //
  // Prefer a row whose test id CONTAINS the address: that is self-verifying, so it
  // cannot submit anything else. The manual row is the fallback for an address with
  // no history — its id names no address, so it only tells us "whatever is typed".
  //
  // A row for a DIFFERENT address is never acceptable. Coinbase lists other
  // contacts and recents alongside ours, and clicking one of those would send to
  // the wrong destination.
  function recipientRow(address) {
    return queryVisible(SEL.favoriteRecipient(address))
      || queryVisible(SEL.recentRecipient(address))
      || queryVisible(SEL.RECIPIENT_MANUAL_ADDRESS);
  }

  // Type the address and confirm it sticks. Typing before the modal hydrates lets
  // React clear the field, so retype on a fresh node until the value holds.
  async function typeRecipientAddress(input, address) {
    for (var attempt = 1; attempt <= 3; attempt++) {
      await typeLikeHuman(input, address);
      await D.sleep(600); // let onChange + any post-hydration re-render settle
      var live = document.querySelector(SEL.RECIPIENT_INPUT) || input;
      if (String(live.value || "").trim().length > 0) return live;
      console.warn("[withdraw] enterRecipient: input cleared after typing (attempt " + attempt + "/3) — likely typed before hydration; retrying");
      input = live;
    }
    throw new Error("withdraw/recipient-input-cleared: the address kept clearing after it was typed (send modal not ready)");
  }

  async function enterRecipient(address) {
    var input = await waitForElement(SEL.RECIPIENT_INPUT, 15000);
    await D.sleep(300); // brief settle so we're not typing into a still-mounting field
    input = await typeRecipientAddress(input, address);

    // Clicking the dropdown row advances off the recipient screen. Re-query the row
    // before each click (a stale node swallows the press) and confirm we advanced.
    for (var attempt = 1; attempt <= 2; attempt++) {
      var row = await pollUntil(function () { return recipientRow(address); },
                               15000, "withdraw/recipient-row-not-found: " + address);
      await humanClick(row);
      var advanced = await pollUntil(function () {
        return queryVisible(SEL.RECIPIENT_INPUT) ? null : true;
      }, 5000).catch(function () { return null; });
      if (advanced) return;
      console.warn("[withdraw] enterRecipient: still on recipient screen after click (attempt " + attempt + "/2); retrying");
    }
    // Don't hard-throw: runSelectionPhase's detectNextScreen surfaces a precise
    // no-next-screen diagnostic if we genuinely never advanced.
  }

  // Synchronous button/clickable text scan, scoped to `root`. Mirrors
  // waitForButtonByText's matching but does a single pass (its callers poll).
  function findButtonByTextSync(text, opts) {
    opts = opts || {};
    var root = opts.root || document;
    var match = opts.match || "exact";
    var requireEnabled = opts.requireEnabled || false;
    var want = String(text).toLowerCase();
    var btns = root.querySelectorAll("button, [role='button'], a");
    for (var i = 0; i < btns.length; i++) {
      var t = (btns[i].textContent || "").trim().toLowerCase();
      var ok = match === "contains" ? t.indexOf(want) !== -1 : t === want;
      if (ok && !(requireEnabled && isDisabled(btns[i]))) return btns[i];
    }
    return null;
  }

  // The live acknowledge control for the network-acceptance warning, or null.
  // `allowFallback` enables the label match — a safety net for a testid drift that
  // callers gate behind a delay so it can't fire mid-transition, and which refuses
  // whenever the l2 container still holds network cells (a live list is never the
  // warning).
  function findNetworkWarningAck(opts) {
    opts = opts || {};
    var direct = queryVisibleLive(SEL.NETWORK_WARNING_CONTINUE);
    if (direct) return direct;
    if (!opts.allowFallback) return null;

    var root = queryVisibleLive(SEL.STEP_L2_SELECTION);
    if (!root) return null;
    if (root.querySelector(SEL.NETWORK_ITEMS_ANY)) return null;

    for (var i = 0; i < SEL.NETWORK_WARNING_ACK_TEXTS.length; i++) {
      var btn = findButtonByTextSync(SEL.NETWORK_WARNING_ACK_TEXTS[i], { root: root, requireEnabled: true });
      if (btn) return btn;
    }
    return findButtonByTextSync(SEL.NETWORK_WARNING_ACK_FRAGMENT, {
      root: root, match: "contains", requireEnabled: true
    });
  }

  // The screen a step container uniquely determines, if any. `l2SelectionStep`
  // maps to null: the acceptance warning shares that container, so it can't be
  // resolved until the content checks (amount anchor / ack button) have run.
  function screenForStep(step) {
    if (step === "assetSelection") return "coin";
    if (step === "destinationTagStep") return "destinationTag";
    if (step === "amountEntry") return "amount";
    return null;
  }

  // True once the warning is behind us: a later step is live, the amount screen's
  // own input is live, or the acknowledge control is gone. Content anchors come
  // first because readActiveStep returns ONE step by reverse document order — with
  // the fading l2 container and the incoming amountEntry both stamped `-active` it
  // can legitimately report the stale one.
  function pastNetworkWarning() {
    var step = readActiveStep();
    if (step && step !== "loaded" && step !== "l2SelectionStep") return true;
    if (queryVisibleLive(SEL.CURRENCY_INPUT)) return true;
    return findNetworkWarningAck({ allowFallback: true }) === null;
  }

  function settledPastWarning(timeoutMs) {
    return pollUntil(function () { return pastNetworkWarning() ? true : null; }, timeoutMs)
      .then(function () { return true; }, function () { return false; });
  }

  // How long the acknowledge button must stay missing-by-testid before the label
  // fallback is allowed to fire. In a normal transition the testid (or a real step
  // name) resolves within a few hundred ms, so the fallback is unreachable on the
  // happy path — its false-positive surface is only "the testid was gone this long".
  var FALLBACK_AFTER_MS = 2000;
  // How long dismissNetworkWarning hunts for the button, and how long it waits for
  // the warning to actually clear after clicking it.
  var WARNING_FIND_MS = 5000;
  var WARNING_CLEAR_MS = 3000;

  // Coinbase keeps the previous step container mounted during fade; `notStep`
  // skips the just-completed step so the race doesn't re-read what we left.
  async function detectNextScreen(opts) {
    opts = opts || {};
    var timeoutMs = opts.timeoutMs || 15000;
    var notStep = opts.notStep;
    var fallbackAfterMs = opts.fallbackAfterMs != null ? opts.fallbackAfterMs : FALLBACK_AFTER_MS;
    var start = Date.now();
    var lastSeen = null;
    while (Date.now() - start < timeoutMs) {
      // Advance signals FIRST. The warning check used to lead, which let an
      // acknowledged warning still fading inside its container out-rank the screen
      // we had actually reached — the selection loop then saw `networkWarning`
      // twice and threw selection-phase-stalled.
      var step = readActiveStep();
      if (step && step !== "loaded" && step !== notStep) {
        lastSeen = step;
        var mapped = screenForStep(step);
        if (mapped) return mapped;
      }
      // Content anchor for amount entry — see pastNetworkWarning on why the step
      // id alone can't be trusted mid-transition.
      if (queryVisibleLive(SEL.CURRENCY_INPUT)) return "amount";
      // Content-identified interstitial: shares l2SelectionStep's id, so neither
      // the step name nor `notStep` can tell it apart.
      if (findNetworkWarningAck({ allowFallback: Date.now() - start >= fallbackAfterMs })) {
        return "networkWarning";
      }
      if (step === "l2SelectionStep" && step !== notStep) return "network";
      await D.sleep(150);
    }
    // Report whether an acknowledge button exists in the document at all: if one
    // does, nothing resolved because every match was stale (or the label drifted),
    // a different diagnosis from "the screen never rendered".
    var staleAck = document.querySelector(SEL.NETWORK_WARNING_CONTINUE) !== null;
    throw new Error('withdraw/no-next-screen: last seen step "' + (lastSeen || "(none)") +
      '" (stale ack in DOM: ' + staleAck + ')');
  }

  // React may bind on pointerdown and the container can mount before its cells —
  // humanClick drives the full pointer sequence; retry once if it didn't advance.
  async function clickAndVerifyAdvance(el, label) {
    void label;
    await humanClick(el);
    var start = Date.now();
    while (Date.now() - start < 1500) {
      if (readActiveStep() !== "assetSelection") return;
      await D.sleep(150);
    }
    var again = document.querySelector('[data-testid="' + el.getAttribute("data-testid") + '"]');
    if (again) await humanClick(again);
  }

  // Tagged error for an address that can't receive the chosen asset — Coinbase
  // shows the asset disabled ("Incompatible" section) or NO sendable asset at all
  // ("No compatible assets"). Terminal + user-actionable (different asset or
  // address); `start`'s catch converts it to a rejected/address_unsupported state
  // rather than clicking a disabled cell and timing out into no-next-screen.
  function addressUnsupportedError() {
    var e = new Error("withdraw/address-unsupported: this asset can't be sent to the recipient address");
    e.zhAddressUnsupported = true;
    return e;
  }

  // True when the asset-selection step is up but EVERY asset cell is disabled — the
  // "No compatible assets" state. Structural (not text/locale based): a single
  // enabled cell means a normal, still-loading list, not an incompatible address.
  function isNoCompatibleAssets() {
    if (readActiveStep() !== "assetSelection") return false;
    var cells = Array.prototype.slice.call(document.querySelectorAll(SEL.COIN_LIST));
    return cells.length > 0 && cells.every(function (c) { return isDisabled(c); });
  }

  // Polls the incompatible state must persist before we trust it — a still-loading
  // list can read as all-disabled for a moment. Mirrors the extension.
  var INCOMPATIBLE_CONFIRM_POLLS = 6;

  async function selectCoin(ticker) {
    var directSelector = SEL.coinDirect(ticker);
    var start = Date.now();
    var incompatibleStreak = 0;
    while (Date.now() - start < 5000) {
      var direct = document.querySelector(directSelector);
      if (direct && !isDisabled(direct)) {
        await clickAndVerifyAdvance(direct, "selectCoin(" + ticker + ")");
        return;
      }
      // Incompatible with the recipient address: the requested asset's own cell is
      // disabled, or no asset is sendable at all. Bail with a specific error (not a
      // no-op click + generic no-next-screen) once the state is confirmed stable.
      var incompatible = (direct !== null && isDisabled(direct)) || isNoCompatibleAssets();
      incompatibleStreak = incompatible ? incompatibleStreak + 1 : 0;
      if (incompatibleStreak >= INCOMPATIBLE_CONFIRM_POLLS) throw addressUnsupportedError();
      await D.sleep(150);
    }
    // 5s without an enabled target cell. Surface incompatibility specifically,
    // else enumerate what's on screen for a useful not-found error.
    if (isNoCompatibleAssets()) throw addressUnsupportedError();
    var items = Array.prototype.slice.call(document.querySelectorAll(SEL.COIN_LIST));
    for (var i = 0; i < items.length; i++) {
      var testId = items[i].getAttribute("data-testid") || "";
      var t = testId.replace("send-asset-selector-cell-", "").replace("-cell-pressable", "").toUpperCase();
      if (t === ticker.toUpperCase()) {
        // Present but disabled for this address — a specific, user-actionable
        // rejection rather than a no-op click.
        if (isDisabled(items[i])) throw addressUnsupportedError();
        await clickAndVerifyAdvance(items[i], "selectCoin");
        return;
      }
    }
    var available = items.map(function (it) {
      var id = it.getAttribute("data-testid") || "";
      return id.replace("send-asset-selector-cell-", "").replace("-cell-pressable", "");
    }).join(", ");
    throw new Error("withdraw/coin-selection-required: " + ticker + " not in [" + (available || "(none detected)") + "]");
  }

  // Returns null when Coinbase skipped network selection (amount already visible).
  async function selectNetwork(network) {
    var which = await waitForAny([SEL.NETWORK_ITEMS, SEL.CURRENCY_INPUT], 15000);
    if (!which) throw new Error("Neither network list nor amount input appeared");
    if (which === SEL.CURRENCY_INPUT) return null;

    await humanDelay(400); // list finishes rendering fees
    var slug = network.toLowerCase();
    var direct = document.querySelector(SEL.networkTestId(slug));
    if (direct) {
      if (isDisabled(direct)) {
        throw new Error('withdraw/network-unsupported-for-address: "' + network +
          '" is shown as disabled — Coinbase does not support this network for the pasted address');
      }
      await humanClick(direct);
      return slug;
    }
    var all = Array.prototype.slice.call(document.querySelectorAll(SEL.NETWORK_ITEMS_ANY));
    var labels = all.map(function (el) {
      var testid = el.getAttribute("data-testid") || "";
      var name = testid.replace("l2-list-item-", "").replace("-cell-pressable", "");
      return isDisabled(el) ? (name + " (disabled)") : name;
    });
    throw new Error('withdraw/network-unavailable: "' + network + '" not in [' + (labels.join(", ") || "(none detected)") + ']');
  }

  // Network-acceptance warning ("Does your recipient accept <ASSET> on <NETWORK>?").
  // The host already chose this network in the payload, so confirm support and
  // advance. The "don't show again" checkbox is left untouched: it mutates an
  // ACCOUNT-WIDE loss-prevention preference (changing what the user sees on their
  // own manual sends), and it's scoped per asset+network anyway, so ticking it
  // wouldn't remove this path. Consequence: the warning recurs on every
  // ETH-on-Base withdrawal, so this path is hot and has to be reliable.
  async function dismissNetworkWarning(opts) {
    opts = opts || {};
    var findMs = opts.findMs || WARNING_FIND_MS;
    var clearMs = opts.clearMs || WARNING_CLEAR_MS;

    // Resolve through the live finder, not waitForElement: that one is a raw
    // querySelector with no visibility filter, so it can hand back a stale node
    // from a fading container and we'd click something inert.
    var ack = await pollUntil(function () {
      return findNetworkWarningAck({ allowFallback: true });
    }, findMs).catch(function () { return null; });
    // Already gone — the flow advanced on its own. Idempotent by design.
    if (!ack) return;

    await humanClick(ack);
    if (await settledPastWarning(clearMs)) return;

    // Coinbase binds on pointerdown and re-renders mid-transition — re-query and
    // click once more, keyed on THIS control clearing rather than a step name.
    var again = findNetworkWarningAck({ allowFallback: true });
    if (again) {
      console.warn("[withdraw] network warning still up after acknowledge; retrying");
      await humanClick(again);
      if (await settledPastWarning(clearMs)) return;
    }
    // Deliberately does not throw: the selection loop re-detects and re-attempts up
    // to its cap, so the phase keeps exactly one failure point (its own budget).
    console.warn("[withdraw] network warning not confirmed dismissed; letting the loop re-detect");
  }

  var RECIPIENT_TYPE_OPTION = {
    "self-custody": SEL.SELF_CUSTODY_OPTION,
    "exchange": SEL.EXCHANGE_OPTION
  };

  // Post-amount recipient-type chooser (some asset/network pairs). No-op when absent.
  async function selectRecipientTypeIfPresent(type) {
    // Race the chooser against the screens that replace it (Send now, travel rule,
    // transfer details). US accounts skip the chooser, so bail if one is already up.
    var which = await waitForAny(
      [SEL.STEP_SELECT_RECIPIENT_TYPE, SEL.SEND_NOW, SEL.BENEFICIARY_NAME, SEL.TRANSFER_PURPOSE],
      10000
    );
    if (which !== SEL.STEP_SELECT_RECIPIENT_TYPE) return;
    var selector = RECIPIENT_TYPE_OPTION[type];
    if (!selector) throw new Error("withdraw/recipient-type-option-not-found: " + type);
    // The step container mounts BEFORE its option buttons render, so a single
    // query races the mount — poll for the option, re-reading the step each time.
    var btn = await pollUntil(function () {
      var s = queryVisible(SEL.STEP_SELECT_RECIPIENT_TYPE);
      return s ? s.querySelector(selector) : null;
    }, 5000, "withdraw/recipient-type-option-not-found: " + type);
    await humanClick(btn);
  }

  // The self-transfer checkbox on the travel-rule form ("I'm transferring to
  // myself"), matched by its own testid — the page carries several checkboxes, so
  // a structural "first checkbox" match would be wrong. Returns the <input> (or
  // null when absent — callers treat that as "fall back to manual entry").
  function selfTransferCheckbox() {
    return document.querySelector(SEL.OWN_ACCOUNT_CHECKBOX);
  }

  function isChecked(box) {
    return !!(box && (box.checked || box.getAttribute("aria-checked") === "true"));
  }

  // The real <input type=checkbox> is visually hidden behind a styled wrapper, so
  // a click on the input itself doesn't register — click the hittable parent
  // (own-account-checkbox-parent), falling back to the input.
  function clickCheckbox(box) {
    var parent = queryVisible(SEL.OWN_ACCOUNT_CHECKBOX_PARENT);
    return humanClick(parent || box);
  }

  // Travel-rule (FATF) "Who are you sending to?" form. Returns "filled" or
  // "not_required" (never appeared).
  //
  // Self-transfer (opts.selfTransfer): the host is sending to the user's OWN
  // account, so tick Coinbase's "I'm transferring to myself" checkbox instead of
  // typing beneficiary details — it auto-fills the beneficiary (name + BR CPF)
  // from the account holder, which also sidesteps the localized/required CPF field
  // we can't populate ourselves. Only when the checkbox is actually present;
  // otherwise falls through to manual entry (which still throws if the host
  // supplied no beneficiary name).
  async function fillTravelRule(data, opts) {
    opts = opts || {};
    var which = await waitForAny([SEL.BENEFICIARY_NAME, SEL.SEND_NOW], 10000);
    if (which !== SEL.BENEFICIARY_NAME) return "not_required";

    if (opts.selfTransfer) {
      var box = selfTransferCheckbox();
      if (box) {
        // Tick it (idempotent). The click lands on the styled parent, so confirm
        // the underlying input toggled and retry once before trusting it.
        if (!isChecked(box)) {
          await clickCheckbox(box);
          await pollUntil(function () { return isChecked(selfTransferCheckbox()) ? true : null; }, 1500)
            .catch(function () { return null; });
          if (!isChecked(selfTransferCheckbox())) await clickCheckbox(box);
        }
        // Coinbase validates async; wait for the submit to enable before clicking.
        var submitSelf = await pollUntil(function () {
          var b = queryVisible(SEL.SUBMIT_BUTTON);
          return (b && !isDisabled(b)) ? b : null;
        }, 5000, "withdraw/travel-rule-self-submit-not-ready");
        await humanClick(submitSelf);
        await D.sleep(500);
        return "filled";
      }
      // Checkbox not found — fall through to manual entry (no regression).
    }

    if (!data || !data.name) throw new Error("withdraw/travel-rule-missing-data");

    var nameInput = await waitForElement(SEL.BENEFICIARY_NAME, 5000);
    nameInput.focus();
    setReactValue(nameInput, data.name);
    await D.sleep(200);

    // Variant A: country-select visible immediately. Variant B: it only appears
    // after clicking Continue.
    var countrySelect = queryVisible(SEL.COUNTRY_SELECT);
    if (!countrySelect) {
      var submit0 = queryVisible(SEL.SUBMIT_BUTTON);
      if (submit0) submit0.click();
      try {
        countrySelect = await waitForElement(SEL.COUNTRY_SELECT, 10000);
      } catch (e) {
        return "filled"; // jurisdiction skipped the country step
      }
    }

    if (data.country) {
      countrySelect.click();
      await D.sleep(400);
      try {
        var opt = await waitForElement(SEL.countryOption(data.country), 5000);
        opt.click();
      } catch (e) { /* option missing — let a downstream error surface it */ }
    }

    var submit = await waitForElement(SEL.SUBMIT_BUTTON, 5000);
    submit.click();
    await D.sleep(500);
    return "filled";
  }

  async function pickDropdownOption(buttonSelector, optionLabel) {
    var container = await waitForElement(buttonSelector, 5000);
    // The testid sits on a wrapper <div>; the real trigger is the listbox
    // <button> inside it. Clicking the wrapper does nothing — resolve the button.
    var button = container.querySelector('button[aria-haspopup="listbox"]')
      || container.querySelector('button, [role="button"]')
      || container;
    await humanClick(button); // cds dropdown ignores a plain .click() — needs pointer events
    await D.sleep(400);
    var deadline = Date.now() + 5000;
    while (Date.now() < deadline) {
      for (var i = 0; i < SEL.DROPDOWN_OPTION_SELECTORS.length; i++) {
        var opts = Array.prototype.slice.call(document.querySelectorAll(SEL.DROPDOWN_OPTION_SELECTORS[i]));
        for (var j = 0; j < opts.length; j++) {
          if (getInnerText(opts[j]).trim() === String(optionLabel).trim()) {
            await humanClick(opts[j]);
            await D.sleep(200);
            return;
          }
        }
      }
      await D.sleep(150);
    }
    throw new Error("withdraw/dropdown-option-not-found: " + optionLabel);
  }

  // Transfer-details form (shown on some regulated corridors): purpose +
  // relationship dropdowns. Returns "filled" / "not_required"; throws if it
  // appeared without data.
  async function fillTransferDetails(data) {
    var which = await waitForAny([SEL.TRANSFER_PURPOSE, SEL.SEND_NOW], 10000);
    if (which !== SEL.TRANSFER_PURPOSE) return "not_required";
    if (!data || !data.purpose) {
      throw new Error("withdraw/transfer-details-missing-data: purpose");
    }
    await pickDropdownOption(SEL.TRANSFER_PURPOSE, data.purpose);

    // Relationship is optional: some jurisdictions/variants omit it (or only
    // render it after a purpose is chosen). Fill it only when actually present.
    var rel = await waitForElement(SEL.TRANSFER_RELATIONSHIP, 2000).catch(function () { return null; });
    if (rel) {
      if (!data.relationship) throw new Error("withdraw/transfer-details-missing-data: relationship");
      await pickDropdownOption(SEL.TRANSFER_RELATIONSHIP, data.relationship);
    }

    var submit = await waitForElement(SEL.TRANSFER_SUBMIT, 5000);
    submit.click();
    await D.sleep(500);
    return "filled";
  }

  // ── Currency-aware amount input ──
  var CURRENCY_SYMBOL = '[data-testid="currency-input"] + span[class*="FlexibleCurrencyInput__StyledSymbol"]';
  var CURRENCY_TOGGLE = 'button[aria-label="switch"]';

  function readCurrencySymbol(root) {
    var el = root.querySelector(CURRENCY_SYMBOL);
    return el ? (getInnerText(el) || null) : null;
  }
  function symbolMatchesRequest(symbol, requested, asset) {
    var isAsset = symbol.toUpperCase() === String(asset).toUpperCase();
    return requested === "asset" ? isAsset : !isAsset;
  }

  // Toggle until the input's symbol matches `requested` mode (asset vs local
  // fiat). Throws if the mode is unreachable — prevents typing "10 USDC" worth
  // of value while the field is in a fiat mode.
  async function ensureCurrencyMode(root, requested, asset) {
    for (var attempt = 0; attempt < 3; attempt++) {
      var symbol = readCurrencySymbol(root);
      if (!symbol) throw new Error("Amount-entry step is missing the currency symbol");
      if (symbolMatchesRequest(symbol, requested, asset)) return symbol;
      var toggle = root.querySelector(CURRENCY_TOGGLE);
      if (!toggle) {
        throw new Error('Coinbase only offers "' + symbol + '" for this flow — cannot switch to "' + requested + '" mode');
      }
      toggle.click();
      await D.sleep(400);
    }
    throw new Error('Could not switch Coinbase amount input to "' + requested + '" mode');
  }

  async function enterAmount(amount, coin) {
    var input = await waitForElement(SEL.CURRENCY_INPUT, 15000);
    if (amount === "max") {
      var maxBtn = await waitForElement(SEL.MAX_BUTTON, 5000);
      await humanClick(maxBtn);
    } else {
      var stepEl = input.closest('[data-testid^="step-"][data-testid$="-active"]') || document.body;
      await ensureCurrencyMode(stepEl, amount.currency, coin);
      await typeLikeHuman(input, amount.value);
    }
    await humanDelay(300);
    var preview = queryVisible(SEL.PREVIEW_SEND);
    if (preview) await humanClick(preview);
    await rejectIfAmountInvalid();
  }

  function classifyAmountError(msg) {
    var lower = msg.toLowerCase();
    if (lower.indexOf("add at least") !== -1 || lower.indexOf("insufficient") !== -1 ||
        lower.indexOf("not enough") !== -1 || lower.indexOf("exceeds your balance") !== -1 ||
        lower.indexOf("more than your balance") !== -1) {
      return "withdraw/insufficient-funds";
    }
    if (lower.indexOf("minimum") !== -1) return "withdraw/below-minimum";
    return "withdraw/amount-validation";
  }

  function readAmountValidationError() {
    var errEl = queryVisible(SEL.AMOUNT_ERROR_MESSAGE);
    var raw = errEl ? getInnerText(errEl) : "";
    var msg = raw.replace(/\s*View balance\s*$/i, "").trim();
    var balanceEl = queryVisible(SEL.ASSET_BALANCE);
    var balance = balanceEl ? getInnerText(balanceEl).replace(/\s+/g, " ") : null;
    if (!msg) return "withdraw/amount-validation: amount rejected (no error text surfaced)";
    var code = classifyAmountError(msg);
    return balance ? (code + ": " + msg + " (balance: " + balance + ")") : (code + ": " + msg);
  }

  // Coinbase validates the amount inline; a rejected value keeps the modal on
  // the amount screen. Surface the error promptly; return once it advances.
  async function rejectIfAmountInvalid() {
    var deadline = Date.now() + 2000;
    while (Date.now() < deadline) {
      if (queryVisible(SEL.SEND_NOW) || !queryVisible(SEL.CURRENCY_INPUT)) return;
      var err = queryVisible(SEL.AMOUNT_ERROR_MESSAGE);
      if (err && getInnerText(err)) throw new Error(readAmountValidationError());
      await D.sleep(150);
    }
  }

  function requireNetwork(payload) {
    if (!payload.network) {
      throw new Error("withdraw/network-required: Coinbase asked for a network but none was provided");
    }
    return payload.network;
  }

  // XRP/ATOM/XLM/EOS prompt for a destination tag (memo) between network
  // selection and amount. Fill it (then Continue) when supplied; the orchestrator
  // calls skip otherwise. Continue stays disabled until Coinbase's async tag-format
  // validation settles, so we wait for the enabled button.
  async function fillDestinationTag(tag) {
    var input = await waitForElement(SEL.DESTINATION_TAG_INPUT, 5000);
    var step = await waitForElement(SEL.STEP_DESTINATION_TAG, 1000);
    input.focus();
    setReactValue(input, tag);
    await D.sleep(200); // let Coinbase's async tag-format validation settle
    var continueBtn = await waitForButtonByText("Continue", {
      root: step, requireEnabled: true, timeoutMs: 5000
    });
    await humanClick(continueBtn);
  }

  async function skipDestinationTag() {
    var skipBtn = await waitForElement(SEL.SKIP_DESTINATION_TAG, 5000);
    await humanClick(skipBtn);
  }

  // Wall-clock bound on the whole selection phase — defence in depth beyond the
  // per-screen caps below and detectNextScreen's own per-iteration timeout. Budget
  // math: 4 legitimate screens × (≤15s detect + handler) ≈ 90s worst case on a
  // genuinely slow page, so 120s never bites a real flow.
  var SELECTION_PHASE_BUDGET_MS = 120000;
  var SELECTION_DETECT_TIMEOUT_MS = 15000;

  // Re-detects tolerated per screen. The acceptance warning gets a few: Coinbase
  // can chain interstitials, and our own acknowledge can be re-read while the
  // container fades out. Re-clicking "Yes, it's supported" is idempotent and moves
  // no money — whereas re-running `network` or `coin` could pick a DIFFERENT
  // network or asset, so those stay single-shot and keep genuine stall detection.
  var SCREEN_ATTEMPT_CAP = { coin: 1, network: 1, networkWarning: 3, destinationTag: 1 };

  function tallyScreens(seen) {
    var parts = [];
    for (var k in seen) {
      if (Object.prototype.hasOwnProperty.call(seen, k)) parts.push(k + "×" + seen[k]);
    }
    return parts.join(", ") || "no screens";
  }

  // Walk Coinbase's selection screens (coin / network / destination-tag) until
  // amount entry. `opts.detect` / `opts.handlers` are test seams that default to
  // the real collaborators, so production always runs the real ones; `opts.budgetMs`
  // overrides the wall-clock budget (used to keep tests fast).
  async function runSelectionPhase(payload, opts) {
    opts = opts || {};
    var detect = opts.detect || detectNextScreen;
    var SELECTION = opts.handlers || {
      coin: { run: function () { return selectCoin(payload.asset); }, step: "assetSelection" },
      network: { run: function () { return selectNetwork(requireNetwork(payload)); }, step: "l2SelectionStep" },
      networkWarning: { run: function () { return dismissNetworkWarning(); }, step: "l2SelectionStep" },
      destinationTag: {
        run: function () {
          return payload.destinationTag
            ? fillDestinationTag(payload.destinationTag)
            : skipDestinationTag();
        },
        step: "destinationTagStep"
      }
    };
    var deadline = Date.now() + (opts.budgetMs || SELECTION_PHASE_BUDGET_MS);
    var prev;
    var seen = {};
    for (;;) {
      var remaining = deadline - Date.now();
      if (remaining <= 0) {
        throw new Error("withdraw/selection-phase-stalled: budget exhausted (" + tallyScreens(seen) + ")");
      }
      // Clamp the detect window to what's left of the budget so the phase can only
      // overrun by one handler's own internal timeout.
      var next = await detect({ notStep: prev, timeoutMs: Math.min(SELECTION_DETECT_TIMEOUT_MS, remaining) });
      if (next === "amount") return;

      var count = (seen[next] || 0) + 1;
      seen[next] = count;
      var cap = SCREEN_ATTEMPT_CAP[next];
      if (count > cap) {
        throw new Error("withdraw/selection-phase-stalled: revisited " + next + " " + count + "× (cap " + cap + ")");
      }

      var handler = SELECTION[next];
      await handler.run(payload);
      prev = handler.step;
    }
  }

  // ── Confirm + 2FA detection + result ──

  function readSendPreview() {
    function text(sel) { var el = queryVisible(sel); return el ? getInnerText(el) : null; }
    return {
      fiatAmount: text(SEL.SEND_PREVIEW_FIAT),
      cryptoAmount: text(SEL.SEND_PREVIEW_CRYPTO),
      recipient: text(SEL.SEND_PREVIEW_RECIPIENT),
      network: text(SEL.SEND_PREVIEW_NETWORK),
      timeEstimate: text(SEL.SEND_PREVIEW_TIME),
      fee: text(SEL.SEND_PREVIEW_FEE)
    };
  }

  // Some flows submit straight from amount/preview into a gate with no separate
  // "Send now" — so also watch the post-send screens and hand off if one appears.
  var POST_SEND_GATES = [
    SEL.IDENTITY_ACCESS_WRAPPER, SEL.OTP_CONTAINER, SEL.OTP_INPUT,
    SEL.TWO_FACTOR_TOTP, SEL.TWO_FACTOR_SMS, SEL.PASSKEY_PROMPT,
    SEL.STEP_RISK_VERIFICATION, SEL.SEND_SUCCESS, SEL.STATUS_COMPLETE_BTN
  ];

  function normalizeAddress(addr) {
    return String(addr || "").trim().toLowerCase().replace(/\s+/g, "");
  }

  // Best-effort check that the recipient shown on the confirm/preview screen is
  // the address the host authorized. The preview may render a contact name and/or
  // a TRUNCATED address ("Sandro … 9LFU…UGd2"), so we assert only what we can and
  // PASS whenever nothing comparable is present — this must never block a send it
  // can't verify, only catch a positive contradiction. DOM-based (not the server
  // commit response the extension uses), so it guards a wrong-row/autofill send,
  // NOT an active DOM attacker.
  function previewRecipientMatches(previewText, authorized) {
    var want = normalizeAddress(authorized);
    if (!want || !previewText) return true;
    if (normalizeAddress(previewText).indexOf(want) !== -1) return true; // full address shown
    // Truncated head…tail (ellipsis U+2026 or "..."). Match on the ORIGINAL text so
    // whitespace still separates a leading contact name from the address.
    var m = previewText.match(/([A-Za-z0-9]{3,})\s*(?:…|\.{2,})\s*([A-Za-z0-9]{3,})/);
    if (!m) return true; // no address-like token → nothing to assert
    var head = m[1].toLowerCase();
    var tail = m[2].toLowerCase();
    if (want.slice(-tail.length) !== tail) return false; // tail is the reliable suffix
    if (want.indexOf(head) === 0) return true;
    // Tolerate a contact name fused onto the head: some suffix of head prefixes want.
    for (var i = 1; i <= head.length - 3; i++) {
      if (want.indexOf(head.slice(i)) === 0) return true;
    }
    return false;
  }

  function recipientMismatchError() {
    return new Error("withdraw/recipient-mismatch: preview recipient does not match the authorized address");
  }

  async function confirmAndSend(authorizedAddress) {
    var which = await waitForAny([SEL.SEND_NOW, SEL.CURRENCY_INPUT].concat(POST_SEND_GATES), 15000);
    if (!which) throw new Error("Neither confirm screen nor amount screen appeared");
    if (which === SEL.CURRENCY_INPUT) throw new Error(readAmountValidationError());
    // Advanced past confirm into a 2FA/risk/success gate — read what we can; the
    // caller's detectAndHandle2fa handles the gate next. (No pre-click verify here:
    // the send already advanced, so there's nothing left to prevent.)
    if (which !== SEL.SEND_NOW) return readSendPreview();

    var details = readSendPreview();
    // Verify the previewed recipient matches what the host authorized BEFORE
    // clicking Send now — refuse to authorize a send to a mismatched address.
    if (!previewRecipientMatches(details.recipient, authorizedAddress)) throw recipientMismatchError();
    await humanDelay(500); // let the preview settle / human "review"
    var sendBtn = await waitForElement(SEL.SEND_NOW, 5000);
    await humanClick(sendBtn);
    return details;
  }

  // Read the value rendered next to a label span (label span → sibling value span).
  function readLabeledValue(root, label) {
    var spans = root.querySelectorAll("span");
    for (var i = 0; i < spans.length; i++) {
      if ((spans[i].textContent || "").trim() === label) {
        var sib = spans[i].nextElementSibling;
        var t = (sib && sib.textContent || "").trim();
        return t || null;
      }
    }
    return null;
  }

  function isOtpScreen() {
    return !!(queryVisible(SEL.OTP_INPUT) || queryVisible(SEL.OTP_CONTAINER) ||
              queryVisible(SEL.TWO_FACTOR_TOTP) || queryVisible(SEL.TWO_FACTOR_SMS));
  }

  function activeGate() {
    if (queryVisible(SEL.STEP_RISK_VERIFICATION)) return "id-verification";
    if (isOtpScreen()) return "otp";
    if (queryVisible(SEL.PASSKEY_PROMPT)) return "passkey";
    return null;
  }

  // Prefer a typed-code method (SMS first, then TOTP) the host can relay over a
  // passkey. Returns true if it switched to an OTP method.
  function chooseOtpMethod() {
    var sms = queryVisible(SEL.TWO_FACTOR_SMS);
    if (sms) { sms.click(); return true; }
    var totp = queryVisible(SEL.TWO_FACTOR_TOTP);
    if (totp) { totp.click(); return true; }
    return false;
  }

  function wasTransferCanceled() {
    return !!queryVisible(SEL.STEP_USER_CANCELLATION);
  }

  // "past 2FA / send accepted": success content, Complete button, or the send
  // modal overlay gone — but NOT while a gate is up or after a cancellation.
  function past2fa() {
    if (wasTransferCanceled()) return false;
    if (activeGate()) return false;
    // Notes match the extension's past2fa (dom.ts) verbatim.
    if (queryVisible(SEL.SEND_SUCCESS)) { bc("past2fa:done", "send-success"); return true; }
    if (queryVisible(SEL.STATUS_COMPLETE_BTN)) { bc("past2fa:done", "complete-btn"); return true; }
    var overlay = document.querySelector(SEL.MODAL_OVERLAY);
    if (!overlay) { bc("past2fa:done", "overlay-absent"); return true; }
    if (!queryVisible(SEL.MODAL_OVERLAY)) { bc("past2fa:done", "overlay-hidden"); return true; }
    return false;
  }

  // Settle the post-confirm state (30s budget). Returns
  // { kind: "none" | "otp" | "passkey" | "processing" | "canceled" |
  //   "id-verification", settled: true }.
  async function detectAndHandle2fa() {
    var outcome = await settlePostConfirm(30000);
    // Coinbase may show a method chooser rather than a code field. Picking SMS or
    // TOTP is a click, so it stays out of the pure classifier.
    if (outcome.kind === "otp") chooseOtpMethod();
    if (outcome.kind === "canceled") bc("risk-gate:canceled");
    return outcome;
  }

  // No network interceptor (deferred) — read the outcome from the success screen.
  async function waitForResult() {
    try {
      await waitForElement(SEL.SEND_SUCCESS + ", " + SEL.STATUS_COMPLETE_BTN, 60000);
    } catch (e) {
      bc("result:timeout");
      return { status: "timeout", completeBefore: null, referenceId: null, sendUuid: null };
    }
    var headline = queryVisible(SEL.SUCCESS_HEADLINE);
    var t = headline ? getInnerText(headline).toLowerCase() : "";
    var failureKeywords = ["fail", "error", "cancel", "falh", "erro"];
    var failed = failureKeywords.some(function (kw) { return t.indexOf(kw) !== -1; });
    // Keep `t` local: the headline can embed the amount/recipient, so never return
    // or breadcrumb it. Report a bounded status instead.
    var status = failed ? "failed" : "success";
    bc("result:success", status);
    return {
      status: status,
      completeBefore: null, referenceId: null, sendUuid: null
    };
  }

  async function finalizeSubmitted(details) {
    var r = await waitForResult();
    return {
      state: "submitted",
      result: {
        status: r.status, completeBefore: r.completeBefore,
        referenceId: r.referenceId, sendUuid: r.sendUuid, details: details
      }
    };
  }

  function toState(outcome, details) {
    switch (outcome.kind) {
      case "canceled": return { state: "rejected", reason: "transfer_canceled" };
      case "otp": return { state: "awaiting-input", kind: "otp", details: details };
      // Passkey is NOT supported: WKWebView can't complete a third-party WebAuthn
      // ceremony and Coinbase offered no code alternative. Reject (terminal) so the
      // host can tell the user to enable SMS/authenticator 2FA.
      case "passkey": return { state: "rejected", reason: "passkey_unsupported" };
      // completeBefore is always null: the risk screen carries no deadline label.
      // Coinbase's commit response has `delayedSendDate`, which needs a network
      // interceptor this design does not build.
      case "id-verification":
        return { state: "awaiting-user-action", kind: "id-verification", details: details, completeBefore: null };
      case "processing": return { state: "processing", details: details };
      default: throw new Error("withdraw/unreachable-2fa-kind: " + outcome.kind);
    }
  }

  // ── Post-confirm classification ──
  //
  // probePostConfirm() performs every DOM read. classifyPostConfirm() is pure, so
  // the precedence rules are unit-testable without a browser
  // (Tests/JSTests/Coinbase/withdraw-classify.test.mjs).
  //
  // "Keep waiting" is the absence of a decisive signal rather than an explicit
  // list of transitional ones. Coinbase renders several containers (the empty
  // identity-access wrapper, the verify-access spinner, the scam-warning intro)
  // that appear BEFORE the outcome is knowable; deciding on any of them WHILE THE
  // BUDGET REMAINS is the bug this replaces. Once the budget expires the classifier
  // must produce an answer regardless of what is on screen — see tier 2 below.
  //
  // Both factories return a FRESH object. Returning a shared constant for the
  // "keep waiting" case would let one caller's stray write poison every later
  // classification, and this file is not in strict mode, so that write would
  // succeed silently.

  function probePostConfirm() {
    var idAccess = queryVisible(SEL.IDENTITY_ACCESS_WRAPPER);
    return {
      userCancellation: !!queryVisible(SEL.STEP_USER_CANCELLATION),
      riskStep: !!queryVisible(SEL.STEP_RISK_VERIFICATION),
      startChallenge: !!queryVisible(SEL.RISK_START_CHALLENGE),
      stepIdVerification: !!queryVisible(SEL.RISK_STEP_IDV),
      idvFailed: !!queryVisible(SEL.RISK_IDV_FAILED),
      scamIntro: !!queryVisible(SEL.RISK_SCAM_INTRO),
      // Named for the field but covers the CONTAINER too, matching isOtpScreen().
      // Newer Coinbase builds render one input per digit inside
      // code-inputs-container; older builds use a single #one-time-code field.
      otpInput: !!(queryVisible(SEL.OTP_INPUT) || queryVisible(SEL.OTP_CONTAINER)),
      twoFactorSms: !!queryVisible(SEL.TWO_FACTOR_SMS),
      twoFactorTotp: !!queryVisible(SEL.TWO_FACTOR_TOTP),
      passkeyPrompt: !!queryVisible(SEL.PASSKEY_PROMPT),
      success: !!(queryVisible(SEL.SEND_SUCCESS) || queryVisible(SEL.SUCCESS_HEADLINE) ||
                  queryVisible(SEL.STATUS_ANIMATION_SUCCESS) || queryVisible(SEL.STATUS_COMPLETE_BTN)),
      // The subset that says, in words, that the send went through: the success
      // panel and its "Você enviou 1,87 USDC" headline. The other two markers are
      // weaker — status-step-complete-button is a generic status-step "Done"
      // control, and status-animation-success appears in none of the 318 captured
      // snapshots — so only these are trusted to overrule a known hold. See the
      // success branch in classifyPostConfirm.
      successConfirmed: !!(queryVisible(SEL.SEND_SUCCESS) || queryVisible(SEL.SUCCESS_HEADLINE)),
      verifyAccessLoader: !!queryVisible(SEL.VERIFY_ACCESS_LOADER),
      // TRUE means "present but empty" — still transitioning. A populated wrapper
      // holds a real 2FA view, which the otp/passkey fields above pick up.
      identityAccessWrapper: !!idAccess && idAccess.children.length === 0,
      statusLoading: !!queryVisible(SEL.STATUS_LOADING),
      stepLoaded: readActiveStep() === "loaded",
      overlay: !!queryVisible(SEL.MODAL_OVERLAY),
      // Set by settlePostConfirm, not read from the DOM.
      budgetExpired: false,
      sawIdVerification: !!moduleState().sawIdVerification
    };
  }

  function decide(kind) { return { kind: kind, settled: true }; }
  function keepWaiting() { return { kind: null, settled: false }; }

  // The ladder has two tiers, and only the first is inherited.
  //
  // TIER 1 — decisive signals. Not invented: it reproduces what past2fa() and
  // activeGate() already composed to.
  //
  //   past2fa    : wasTransferCanceled() -> activeGate() -> SEND_SUCCESS
  //   activeGate : risk -> isOtpScreen() -> passkey
  //   compose    : cancel > risk > otp > passkey > success
  //
  // TIER 2 — budget-expiry resolution, reached only when tier 1 found nothing.
  // This part is NEW; the legacy code had no notion of a budget, which is why it
  // decided on transitional containers. Order: sticky hold > modal-gone > still up.
  // Derived from exploration capture d9d96c27, not from the legacy functions.
  //
  // Two tier-1 properties are load-bearing, both pinned by tests:
  //  - a live GATE outranks a success screen. Reporting a completed send while a
  //    gate is up is the failure this work removes; a stale gate self-corrects on
  //    the next poll.
  //  - a typed-code method outranks a passkey. Passkey maps to the TERMINAL
  //    passkey_unsupported, so the wrong order strands a user who had SMS
  //    available. This deliberately overrides detectAndHandle2fa's old order,
  //    which ranked passkey above a bare code field because chooseOtpMethod()
  //    only ever matched the SMS/TOTP buttons.
  function classifyPostConfirm(p) {
    if (p.userCancellation) return decide("canceled");
    if (p.riskStep && (p.startChallenge || p.stepIdVerification || p.idvFailed)) {
      return decide("id-verification");
    }
    if (p.otpInput || p.twoFactorSms || p.twoFactorTotp) return decide("otp");
    if (p.passkeyPrompt) return decide("passkey");
    // A session that has already reported a hold needs UNAMBIGUOUS evidence before
    // it may report success. If Coinbase states the send went through, believe it —
    // arguing with that would strand a completed transfer. But the weaker markers
    // must not overrule a known hold: the same asymmetry as everywhere else here, a
    // wrong hold self-corrects on the next poll, a wrong success loses the send.
    if (p.success && (!p.sawIdVerification || p.successConfirmed)) return decide("none");
    // No decisive signal. Keep waiting unless the clock has run out — past that
    // point every branch below MUST settle, or settlePostConfirm has no answer.
    if (!p.budgetExpired) return keepWaiting();
    // A session that already reported a hold can NEVER resolve to success here.
    // Coinbase's risk screen does not advance when the check clears elsewhere
    // (capture d9d96c27), so a vanished screen means we lost track of a held
    // send, not that it went through.
    if (p.sawIdVerification) return decide("id-verification");
    // The scam-warning intro, once the budget is gone. It is listed above as a frame
    // that renders BEFORE the outcome is knowable, and that holds — but it is also
    // the settled state of the "this transfer looks like a scam" screen, which
    // Coinbase blocks on and never advances. Measured on Android: it held across
    // every poll for over a minute with no other risk marker appearing, and because
    // nothing reported the gate this fell through to "processing", so the page was
    // never presented and the user could not answer it. Tier 2 keeps both readings:
    // a transitional intro still gets the whole budget to become something else.
    if (p.riskStep && p.scamIntro) return decide("id-verification");
    // Last resort: the send modal is gone and no success screen ever rendered.
    // Coinbase closes the modal on some success variants, so treat it as done.
    if (!p.overlay) return decide("none");
    return decide("processing");
  }

  // Record a hold so every later poll inherits it. See classifyPostConfirm's
  // sawIdVerification guard.
  function rememberOutcome(outcome) {
    if (outcome.kind === "id-verification") moduleState().sawIdVerification = true;
    return outcome;
  }

  // Poll until a decisive signal appears, then classify. On budget exhaustion,
  // classify once more with budgetExpired so a decision is always produced.
  //
  // Replaces a fixed `sleep(1500)`, which landed between Coinbase unmounting the
  // 2FA loader and mounting the risk screen and so decided on neither.
  async function settlePostConfirm(budgetMs) {
    var deadline = Date.now() + (budgetMs || 0);
    for (;;) {
      var outcome = classifyPostConfirm(probePostConfirm());
      if (outcome.settled) return rememberOutcome(outcome);
      if (Date.now() >= deadline) break;
      await D.sleep(250);
    }
    var last = probePostConfirm();
    last.budgetExpired = true;
    return rememberOutcome(classifyPostConfirm(last));
  }

  // ── OTP / poll (continue path) ──

  // Persisted across start→continue on window (the modal page isn't navigated,
  // so it survives; degrades to empty details if a reload ever wipes it).
  function moduleState() {
    if (!window.__zhWithdrawState) window.__zhWithdrawState = { details: null };
    return window.__zhWithdrawState;
  }

  function dispatchPaste(input, text) {
    try {
      var dt = new DataTransfer();
      dt.setData("text/plain", text);
      input.dispatchEvent(new ClipboardEvent("paste", { clipboardData: dt, bubbles: true, cancelable: true }));
    } catch (e) {}
  }

  // Newer Coinbase builds render one input per digit; older builds use a single
  // field. Distribute one digit per box when there are several, else set the
  // whole value (+ paste for variants that only split on paste).
  function fillOtpCode(firstInput, code) {
    var container = firstInput.closest(SEL.OTP_CONTAINER) || queryVisible(SEL.OTP_CONTAINER);
    var boxes = container ? Array.prototype.slice.call(container.querySelectorAll("input")) : [firstInput];
    if (boxes.length <= 1) {
      firstInput.focus();
      setReactValue(firstInput, code);
      dispatchPaste(firstInput, code);
      return;
    }
    var digits = String(code).split("");
    for (var i = 0; i < boxes.length; i++) {
      boxes[i].focus();
      setReactValue(boxes[i], digits[i] || "");
    }
  }

  // Type the code. true = accepted (past2fa flipped or the code screen advanced);
  // false = Coinbase cleared the field (bad code). Throws on timeout (a hang).
  async function enterOtp(code) {
    await waitForAny([SEL.OTP_INPUT, SEL.OTP_CONTAINER, SEL.IDENTITY_ACCESS_WRAPPER], 15000);
    if (past2fa()) return true;
    // Coinbase may still be showing the method chooser rather than a code field.
    // The poll that reported `otp` already tried to pick a method, but it runs
    // without the page presented, so don't depend on that click having landed —
    // otherwise waitForElement below burns 15s and throws.
    var choseMethod = false;
    if (!queryVisible(SEL.OTP_INPUT) && chooseOtpMethod()) {
      choseMethod = true;
      await D.sleep(300);
    }
    var input;
    try {
      input = await waitForElement(SEL.OTP_INPUT, 15000);
    } catch (e) {
      // A method WAS chosen and the field still never appeared. That is a different
      // failure from "no field ever existed", with a different owner, so it gets its
      // own name — `element_not_found:#one-time-code` reads as a Coinbase layout
      // change and is what made the production report unreadable (AUTH-4245).
      if (choseMethod) {
        throw new Error("withdraw/otp-field-missing-after-method-choice: " + SEL.OTP_INPUT);
      }
      throw e;
    }
    fillOtpCode(input, code);
    await D.sleep(300);
    var start = Date.now();
    while (Date.now() - start < 15000) {
      if (past2fa()) return true;
      if (Date.now() - start > 1500) { // give React ~1.5s before reading the field
        var current = document.querySelector(SEL.OTP_INPUT);
        if (current && current.value === "") return false; // rejected: field cleared
        if (!queryVisible(SEL.OTP_INPUT) && !queryVisible(SEL.OTP_CONTAINER)) return true; // advanced
      }
      await D.sleep(500);
    }
    throw new Error("withdraw/otp-timeout: Coinbase didn't accept or reject the code");
  }

  // ─── Entry points ───────────────────────────────────────────────────

  function emptyDetails() {
    return {
      fiatAmount: null, cryptoAmount: null, recipient: null,
      network: null, timeEstimate: null, fee: null
    };
  }

  function fundsNotAvailableRejection() {
    return { state: "rejected", reason: "funds_not_available" };
  }

  async function continueInner(payload) {
    var details = moduleState().details || emptyDetails();
    if (!payload || typeof payload !== "object" || !("kind" in payload)) {
      throw new Error("withdraw/invalid-payload: kind");
    }

    if (payload.kind === "otp") {
      if (!payload.code || !/^\d{6}$/.test(payload.code)) {
        throw new Error("withdraw/invalid-payload: code (expected 6 digits)");
      }
      bc("continue:otp");
      var accepted = await enterOtp(payload.code);
      if (!accepted) return { state: "rejected", reason: "otp_rejected" }; // retriable
      var outcome = await detectAndHandle2fa();
      bc("2fa-outcome", outcome.kind);
      if (outcome.kind === "none") return await finalizeSubmitted(details);
      return toState(outcome, details);
    }

    if (payload.kind === "poll") {
      bc("continue:poll");
      // Same classifier as `start`, shorter budget — so the two cannot drift.
      // Parked at id-verification this returns id-verification every time:
      // Coinbase's risk screen does not advance when the check clears in
      // another app, and zerohash's own systems report the final disposition.
      var polled = await settlePostConfirm(10000);
      bc("poll-outcome", polled.kind);
      if (polled.kind === "canceled") bc("risk-gate:canceled");
      if (polled.kind === "otp") chooseOtpMethod();
      if (polled.kind === "none") return await finalizeSubmitted(details);
      return toState(polled, details);
    }

    throw new Error("withdraw/invalid-payload: unknown kind");
  }

  window.__zhWithdraw = {
    // Drive Send → forms → preview → "Send now", then detect & return the 2FA state.
    start: async function (params) {
      try {
        bc("open-send-modal");
        await openSendModal();
        bc("enter-recipient");
        await enterRecipient(params.address);
        await runSelectionPhase(params);
        bc("enter-amount");
        await enterAmount(params.amount, params.asset);
        await selectRecipientTypeIfPresent(params.recipientType || "self-custody");
        // Self-transfer: the webapp sends transferDetails.purpose "Transfer to my
        // own account" for sends to the user's own account. Signal it so
        // fillTravelRule ticks the "I'm transferring to myself" checkbox (which
        // auto-fills the beneficiary + BR CPF) rather than typing beneficiary data.
        var isSelfTransfer = !!(params.transferDetails &&
          params.transferDetails.purpose === "Transfer to my own account");
        await fillTravelRule(params.travelRule, { selfTransfer: isSelfTransfer });
        await fillTransferDetails(params.transferDetails);
        bc("confirm-send");
        var details = await confirmAndSend(params.address);
        moduleState().details = details; // persist for continue()
        bc("detect-2fa");
        var outcome = await detectAndHandle2fa();
        bc("2fa-outcome", outcome.kind);
        if (outcome.kind === "none") return await finalizeSubmitted(details);
        return toState(outcome, details);
      } catch (e) {
        // A prior transfer pending verification blocks this send — terminal, but
        // surface its details (not a generic error) so the host can tell the user
        // what to resolve at coinbase.com.
        if (e && e.zhPendingTransfer) {
          return { state: "rejected", reason: "pending_transfer", pendingTransfer: e.zhPendingTransfer };
        }
        // The recipient address can't receive the chosen asset ("No compatible
        // assets" / disabled cell) — terminal + user-actionable, so surface a
        // specific rejection instead of the generic coin/no-next-screen error.
        if (e && e.zhAddressUnsupported) {
          return { state: "rejected", reason: "address_unsupported" };
        }
        if (e && e.zhFundsNotAvailable) {
          return fundsNotAvailableRejection();
        }
        if (isHoldModalPresent()) {
          return fundsNotAvailableRejection();
        }
        throw e;
      }
    },
    // OTP/poll follow-up on the SAME live session.
    continue: async function (payload) {
      try {
        return await continueInner(payload);
      } catch (e) {
        if (isHoldModalPresent()) {
          return fundsNotAvailableRejection();
        }
        throw e;
      }
    },
    // Teardown only — never aborts the transfer at Coinbase.
    //
    // The coordinator dismisses the WebView unconditionally
    // (WithdrawCoordinator.swift:138-145), so this needs to do nothing. It
    // deliberately does NOT click Coinbase's cancel button: the only screen that
    // has one is the risk screen, and that is exactly when the user has been sent
    // to the Coinbase app to finish the identity check. Closing the host modal
    // fires withdraw.cancel, so clicking would throw away the held transfer.
    cancel: async function () {
      return { cancelled: false };
    },
    // Test seam. Consumed only by Tests/JSTests/Coinbase; nothing in the SDK
    // reads it. SEL is exposed so the test harness never has to duplicate a
    // selector string — a duplicate can drift, and drift here fails silently.
    __internals: {
      SEL: SEL,
      recipientRow: recipientRow,
      probeSendEntry: probeSendEntry,
      classifySendEntry: classifySendEntry,
      classifyPostConfirm: classifyPostConfirm,
      probePostConfirm: probePostConfirm,
      settlePostConfirm: settlePostConfirm,
      readActiveStep: readActiveStep,
      queryVisibleLive: queryVisibleLive,
      findNetworkWarningAck: findNetworkWarningAck,
      pastNetworkWarning: pastNetworkWarning,
      detectNextScreen: detectNextScreen,
      dismissNetworkWarning: dismissNetworkWarning,
      runSelectionPhase: runSelectionPhase,
      previewRecipientMatches: previewRecipientMatches,
      isHoldModalPresent: isHoldModalPresent,
      awaitRecipientOrPendingBlock: awaitRecipientOrPendingBlock
    }
  };
})();
