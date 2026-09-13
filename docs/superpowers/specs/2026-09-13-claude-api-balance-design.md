# Claude API Balance — Isolated Console Session

**Status:** Direction and persistent session approved; written specification awaiting review.
**Date:** 2026-09-13

## Outcome and evidence

Show the Claude API prepaid balance in the main dashboard popover, separately
from subscription quota. This is an extension to the existing API billing-link
feature, not a change to subscription authentication or quota calculation.

The user completed Console login in the Codex browser. Read-only DOM inspection
found one `Credit balance` section containing `$5.00` and `Remaining balance`,
separate from spend limits and invoices. This proves page-text extraction in
that browser only. Native WKWebView login, session persistence, organization
identification, and refresh are not yet verified. Browser session data must not
be imported into Needlbar. No private account, payment, address, or invoice data
belongs in fixtures, logs, or this specification.

## Selected approach and alternatives

Use a Claude API-specific persistent WebKit website data store. The user has
explicitly approved remembering this login in Needlbar and deleting the local
session on disconnect. Compared with a process-only store this avoids requiring
login after every app restart, but requires explicit consent and reliable data
deletion. Keeping only the external link remains the fallback if native login
cannot work safely; it does not provide an in-popover balance.

The macOS 14 target supports identifier-based persistent WKWebsiteDataStore
creation and deletion. This does not guarantee the provider permits embedded
login; native acceptance remains a prerequisite for shipping the integration.

## Scope and user experience

- Claude API only. OpenAI billing links and Cursor remain unchanged.
- Settings adds `Connect Claude API`, an explanation that the login session is
  stored on this Mac by Needlbar, and `Disconnect and clear session`.
- Existing opt-in API row visibility remains independent of connecting. Merely
  enabling the billing-link toggle does not initiate login or grant storage
  consent. Hiding a row does not silently delete a session.
- Connect opens a dedicated visible Console window. The user signs in directly
  with Claude. On successful login, read the billing balance without requiring
  the user to copy data or enter an API key.
- A valid observation displays `Claude API` with the page's amount, selected
  organization label, and last-checked time. Preserve the observed currency
  notation; a dollar symbol alone must not be promoted to a verified ISO code.
- `Refresh balance` opens the dedicated window and performs a new observation,
  reusing its session where valid. No timer, startup fetch, quota-refresh hook,
  or hidden background polling is introduced in this first increment.
- The amount is held only in memory. After app restart show `Refresh to check`
  rather than a fabricated connected state or old balance. The saved session
  may avoid login, but the provider can still require reauthentication.
- Keep `Open billing page` as an explicit external-browser fallback. Its session
  remains independent and is never copied back into Needlbar.
- No new menu-bar value, widget, Analytics feature, payment operation, auto-reload
  change, admin/API key, or subscription login behavior is included.

## Architecture and privacy boundary

An AppKit/WebKit session coordinator owns one provider-specific UUID store,
the window, navigation policy, and extraction lifecycle. It does not use the
default WebKit store or the existing ProviderLoginCoordinator. Closing the
window cancels that observation but does not delete the approved saved session.

A small value/state layer owns only the validated amount and currency notation,
organization display label, observation time, and safe status/error categories.
SwiftUI consumes this state and participates in existing popover measurement.
Rust, the C ABI, token history, subscription quota repositories, and the existing
refresh coordinator gain no billing responsibilities.

WebKit manages cookies and website storage internally. Needlbar must not export
or log cookies, tokens, passwords, raw HTML, network responses, or page-wide
text. The extractor returns only the necessary validated balance metadata.
Existing browser profiles, CLI credentials, and Keychain items are not read or
modified for this feature. No real user account data is committed as a fixture.

## Navigation and extraction safety

The entry point is the fixed HTTPS billing URL:
`https://platform.claude.com/settings/billing`.

Read only the expected main-frame billing origin/path. Find the unique
`Credit balance` section and its unique `Remaining balance` amount; do not use
the first currency value anywhere on the page. Reject absent, ambiguous,
malformed, or unsupported representations rather than guessing. A genuine
explicit zero is valid, but missing data and errors are never converted to zero.

Identify the selected organization from an explicit organization control or
label, not a billing address or inferred account name. If identity cannot be
established, do not publish an unqualified numeric observation. Organization
changes invalidate old results before another result can be shown.

Only observed and reviewed login redirect destinations may be allowed. No
wildcard HTTPS navigation or guessed private API endpoints. Never extract data
on an identity-provider page. CAPTCHA, MFA, and credentials are handled by the
user; browser security restrictions are not bypassed. Unsupported embedded
authentication keeps the external link available and reports the limitation.

## Failure, cancellation, and disconnect

Represent disconnected, checking, observed, reauthentication-required,
unavailable/page-changed, and clearing-session states explicitly. A refresh
failure must not leave a prior result looking current; show a safe failure
message and retry. Clear the displayed amount on reauthentication or uncertain
organization identity. No failures alter subscription quota state.

Serialize observations and use a generation token to discard results after
window cancellation, organization changes, or disconnect. Bound observation
waiting and offer retry rather than indefinitely waiting for selectors.

Disconnect first invalidates ongoing work and clears in-memory results, then
releases all WebViews using the store and removes that dedicated data store.
Only acknowledge successful deletion after completion. On deletion failure,
retain a retryable `Couldn't clear Claude API session` state and prevent session
reuse. Persist a non-secret pending-clear marker so an app restart retries
cleanup instead of silently reopening the old session. This is local session
removal, not a claim of provider-side token revocation.

## Verification and delivery gates

1. Before production wiring, verify dedicated native login, exact redirect
   origins, organization labeling, and balance extraction. Browser-only success
   is not native acceptance. Stop if safe native authentication is unsupported.
2. Use synthetic fixtures for valid/zero/malformed/ambiguous amounts, unrelated
   invoice/spend values, missing organization, and changed DOM. Return only the
   whitelisted result fields.
3. Test session isolation, consent, window-close behavior, restart behavior,
   explicit refresh only, cancellation/generation guards, disconnect completion,
   cleanup failure/retry, and pending cleanup across restart.
4. Test provider visibility, dynamic popover sizing, fallback navigation, and
   unchanged subscription quota/login, OpenAI, Cursor, and other surfaces.
5. Run focused tests followed by `make test`. Native acceptance separately
   verifies login, refresh, app restart reuse, and disconnect on the user's Mac.
6. Do not claim automatic polling, full provider compatibility, reinstall,
   release, or publication without separately performing those steps.

## Next gate

Review this written specification, then prepare the implementation plan. The
first implementation milestone is native feasibility, not a public release.
