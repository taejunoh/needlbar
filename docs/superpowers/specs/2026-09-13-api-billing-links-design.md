# Needlbar API Billing Links Design

**Status:** User approved on 2026-09-13; implementation verified on
2026-09-13 in synthetic/test-only validation; branch remains unmerged,
unpushed, and not installed
**Date:** 2026-09-13
**Scope:** Add opt-in links to the Claude API and OpenAI API billing dashboards.

## 1. Outcome and boundaries

Needlbar will offer navigation to provider billing pages, not billing data.
The links are distinct from Claude/Codex subscription quota, local usage, and
estimated-cost presentation. This increment does not add balance retrieval,
automatic account detection, admin/API keys, manual budgets, cost reports, or
quota polling changes. Cursor remains unchanged.

Each supported provider gets a `Show API billing link` preference, defaulting
off. The Settings provider page remains the control plane: its existing
surface visibility and metric controls stay unchanged, and enabling this
preference never enables a hidden provider, changes order, or changes quota
authentication. The main dashboard popover renders the opt-in action beneath
the matching visible provider; hidden providers must not gain a new row.
Settings can still configure the preference for a hidden provider. Menu-bar
text, widgets, and Analytics do not gain billing actions.

The visible provider labels and destinations are fixed:

| Label | Destination |
| --- | --- |
| Claude API | `https://platform.claude.com/settings/billing` |
| OpenAI API | `https://platform.openai.com/settings/organization/billing/overview` |

Both destinations are fixed official HTTPS URLs. The Claude destination is the
official Claude Console Billing page verified from Anthropic's documentation
(which directs users to Console Settings > Billing) and by opening the URL on
2026-09-13; the OpenAI destination was likewise opened on that date.

## 2. UI and action contract

Add a small API Billing section alongside the existing provider Connection
section. It contains the opt-in toggle and destination label for Claude and
Codex. The dashboard renders the action only when the preference
is enabled and that provider is visible there; the action is labelled
`Check balance` with `Claude API` or `OpenAI API`. The action is deliberately navigation copy:
it must not claim that Needlbar knows a balance, zero, freshness, or account.
The row participates in the existing content-height measurement, so hiding it
removes its height. Subscription sign-in/status and Cursor Spending retain their existing copy
and behavior.

An explicit click opens the fixed HTTPS URL in the macOS default browser via a
provider-owned action router. No request, background task, login, credential
access, or account lookup occurs before or after opening. The URL cannot be
constructed from user input. If the opener reports failure, retain the action
and show an accessible inline `Couldn't open billing page. Try again.` state;
Retry invokes the same fixed action and clears the error only on success.

## 3. Ownership, persistence, and invariants

`NeedlbarCore`'s provider configuration is the source of truth. Add one
boolean for Claude and one for Codex, persisted with the existing provider
configuration using keys
`needlbar.systemMonitor.ai.<provider>.apiBillingLink.visible`. Missing or
malformed values read as `false`; there is no legacy migration. A setter
writes only the canonical configuration and posts the existing configuration
change notification. Reads do not write defaults or refresh data.

SwiftUI owns the toggle and accessible row; the AppKit-facing action owns
`NSWorkspace` opening and reports the Boolean result. Rust, the C ABI,
`RefreshCoordinator`, quota repositories, usage aggregation, widgets, and
local cost reporting gain no responsibility or behavior.

## 4. Verification contract

Implementation must add focused tests for:

1. fresh defaults, strict Boolean persistence, malformed-value fallback, and
   round-trip settings for both supported providers;
2. exact provider labels, exact fixed URLs, and action routing to the default
   browser without network/account calls;
3. enabled/disabled rendering, provider/surface visibility gating, and stable
   layout when the action is absent or present;
4. opener failure, accessible error/retry, and success recovery; and
5. unchanged subscription sign-in/quota, Cursor Spending, usage, cost, and
   refresh behavior.

Run focused Settings/action tests during implementation, then `make test` as
the implementation gate. Focused Swift coverage and `make test` passed on
2026-09-13. Native visual and interaction acceptance is not claimed by this
design record.
