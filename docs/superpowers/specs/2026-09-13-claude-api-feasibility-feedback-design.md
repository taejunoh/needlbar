# Claude API Feasibility Harness — Feedback Contract

**Status:** Approved for implementation.
**Date:** 2026-09-13

## Purpose and boundary

Improve the native feasibility harness so a visible blank/error state and its
safe diagnostic event are observable immediately. This is review-only feedback,
not a Claude API balance feature, authentication change, or WebKit diagnosis.
It preserves the existing fixed store UUID and any session already in that
store. The new feedback path never reads, exports, clears, or logs credentials,
cookies, account identifiers, raw HTML, page text, userinfo, or raw error
descriptions. The existing counts-only DOM probe remains unchanged.

No production targets, dashboard, settings, providers, C ABI, Rust, packages,
installation, release, background work, automatic retry, polling, refresh hook,
or navigation origins change. The only approved main-frame origin remains the
existing `https://platform.claude.com:443`; this feedback must not turn an
observed event into permission for another origin.

## Visible feedback states

The review window owns a compact inline status beside the existing Inspect
button. It begins as **Loading approved billing page** when a navigation begins.
On the exact approved billing route it becomes **Page loaded — authentication
unproven**. Route completion is deliberately not “authenticated,” “connected,”
or a balance observation.

The explicit Inspect action displays either **Inspection counts: sections N,
labels N — success unproven**, **Inspection unavailable**, or **Inspect the
approved billing page first**. Counts are DOM-shape evidence only; even `1/1`
does not establish login, selected organization, session reuse, amount parsing,
or balance-refresh feasibility.

For a current, allowed provisional failure, the status is **Unavailable:
`<domain>` (`<code>`)**. The format permits the observed `NSURLErrorDomain
(-1009)` and otherwise exposes only the sanitized NSError domain and numeric
code. It never shows localized descriptions, failing URLs, query strings,
fragments, userinfo, or provider page content. A blocked navigation remains a
separate sanitized-origin policy event, not an unavailable-route claim.

## Event and lifecycle contract

Each visible transition emits a one-line, prefixed, sanitized event immediately
to the harness log and flushes it; users do not need to close the window to see
loading, route-loaded, inspection, or failure evidence. Events contain only a
fixed event name, approved origin/route boolean, existing sanitized blocked
origin, DOM counts, or sanitized failure domain/code. They omit timestamps,
raw URLs, raw errors, page data, and
credentials.

Starting a navigation advances the navigation generation and makes Loading the
only current status. Every asynchronous callback captures that generation and
the WebView identity. A replacement navigation or window close advances the
generation, stops loading, and invalidates pending inspection/failure results.
Only a still-current matching callback may alter status or emit its result; a
stale load, JavaScript completion, or error cannot overwrite later feedback.
Closing remains a normal exit and neither retries nor clears the store.

## Alternatives and decision

Use inline status plus flushed sanitized events. Inline-only feedback would
lack retained diagnostic evidence; logs-only would leave the window unexplained
to the user. A richer DOM/network inspector is out of scope because it increases
the risk of exposing account or page data and does not answer the immediate
load-failure question.

## Verification and non-claims

Add native feedback tests with synthetic state/event inputs only: loading,
route loaded but authentication unproven, count output but success unproven,
sanitized `NSURLErrorDomain/-1009`, absence of raw error/userinfo, and
generation/close stale-result rejection. They perform no login, live network,
store clearing, or credential access. Run the focused support tests, then
`make test` before recording implementation evidence.

The prior real `-1009` observation remains unexplained. Passing synthetic tests
proves only feedback behavior, not a fix for that error, native authentication,
session reuse, or balance extraction. After written review, a separate approved
implementation plan may define the smallest harness change.
