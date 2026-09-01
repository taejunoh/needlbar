# Needlbar Public-Facing README Refresh Design

**Status:** Approved design for implementation planning.

**Scope:** Refresh the repository root `README.md` so a prospective Needlbar
user can understand what the product is, obtain the public release, install it,
and find the relevant privacy, provider, development, and limitation details.
This is a documentation-only change. It does not change product behavior,
release artifacts, `docs/STATUS.md`, or any provider contract.

## 1. Purpose and constraints

The current README is accurate in important places but is organized around
release history and implementation milestones. The refresh makes it user-first
and current-state oriented while retaining the factual boundaries enforced by
the release documentation contract.

The approved source of truth is the current public release record in
`docs/STATUS.md`: Needlbar v0.2.2 is publicly available for macOS 14 or later
on Apple Silicon. The README must not reinterpret historical tagless runs,
pre-release preparation, or the unresolved v0.2.1 native acceptance as a
public-release claim.

The README remains concise enough for a new user to scan. Detailed provider
paths, architecture, privacy policy, security reporting, contribution rules,
and approved design records remain linked documentation rather than being
duplicated in full.

## 2. Information architecture

Rewrite the README in this order:

1. Intro: one short product description and one short local-first/privacy
   boundary paragraph.
2. Availability and download: current public availability, requirements,
   exact release ZIP and checksum links, verification, and installation in
   `/Applications`.
3. Current features: the shipped usage/quota overview, provider modules,
   settings/authentication, v0.2.0 local JSON export, v0.2.1 widget and
   notification behavior, and v0.2.2 local repository analytics.
4. Provider support: Claude Code, Codex, and Cursor, with source and quota
   differences stated in user terms.
5. Privacy and local-first boundaries.
6. Development: build, test, run, and local package commands.
7. Known limitations and documentation links.
8. Credits and licenses.

Do not retain a milestone section titled `What v0.1 does`, a heading or copy
that calls v0.2.1 unreleased, or a prominent maintainer-only tagless-RC
history section. The README may retain one brief tagless-validation boundary
sentence near development/release notes because the existing contract requires
the word `tagless`; it must not include run IDs, RC chronology, or imply that a
tagless validation artifact is downloadable or public.

## 3. Availability, download, checksum, and installation

The Availability section must use these exact public-release strings, with no
prepared/future wording:

```text
Needlbar v0.2.2 is publicly available for macOS 14 or later on Apple Silicon.
```

```markdown
[Download Needlbar v0.2.2 for Apple Silicon](https://github.com/taejunoh/needlbar/releases/download/v0.2.2/Needlbar-macos-arm64.zip)
```

Provide a second direct link to the published sidecar at the same release
path:

```markdown
[Download the SHA-256 checksum](https://github.com/taejunoh/needlbar/releases/download/v0.2.2/Needlbar-macos-arm64.zip.sha256)
```

The sidecar's exact filename is `Needlbar-macos-arm64.zip.sha256`. The README
must explain that it is the SHA-256 checksum for the ZIP and show the
verification command:

```bash
shasum -a 256 -c Needlbar-macos-arm64.zip.sha256
```

The public signing statement must appear exactly as follows:

```text
The public artifact is Developer ID-signed and notarized.
```

Installation guidance is explicit and short:

1. Download the ZIP and checksum sidecar from the v0.2.2 GitHub Release.
2. Run the checksum command from the directory containing both files.
3. Open the verified ZIP and drag `Needlbar.app` into `/Applications`.
4. Launch Needlbar from `/Applications`; it appears in the macOS menu bar.

The local-build boundary must retain this exact sentence:

```text
The local package is ad-hoc signed and is not a substitute for the public artifact.
```

The surrounding copy may explain that `make package` creates the local
Apple-Silicon evaluation bundle, but must not call that archive the public
download or suggest that local ad-hoc signing is equivalent to Developer ID
signing and notarization.

The README must retain this exact native acceptance caveat:

```text
Native signed macOS 14 arm64 Widget Gallery/App Group and notification-permission acceptance still require external evidence; the local macOS 26 build is not that acceptance.
```

This caveat is a known limitation of the native acceptance evidence, not a
claim that the public ZIP is unavailable. Do not claim Widget Gallery
discovery, App Group runtime, deep-link behavior, notification permission, or
macOS 14 native acceptance beyond that sentence.

## 4. Current feature presentation

Use current capabilities as feature groups rather than version-history
headings. The claims below are the complete v0.2.2 public feature scope.

### Usage and quota monitoring

Needlbar is a native macOS menu-bar monitor for Claude Code, Codex, and Cursor.
It presents locally aggregated token usage and estimated cost together with
provider quota windows and reset times. Overview combines today’s tokens and
estimated cost, the most constrained eligible quota, a seven-day usage chart,
provider status, and Settings. Provider views show today’s usage/cost,
token-split detail, quota/reset information, freshness, and safe recovery
states. Usage and quota are independent refresh streams; a failure in one does
not replace a previously valid value with zero.

Settings controls visible modules and title metrics. Claude and Codex expose
provider-owned browser sign-in actions (`claude auth login --claudeai` and
`codex login`); Needlbar does not implement a second OAuth flow. Cursor has no
Needlbar credential or connection workflow.

### Local snapshot export

Settings includes **Export snapshot…**, a user-initiated JSON export of the
current normalized provider snapshot. It does not refresh, authenticate,
access Keychain, or upload data. The export contains only the approved
normalized usage, quota, freshness, and safe status fields; it excludes
credentials, account identifiers, raw paths/responses, prompts, assistant
responses, source code, and raw diagnostics.

### Widget and quota notifications

The released app includes one medium Overview widget backed by a sanitized local
projection. The widget does not refresh providers. Quota notifications are off
by default, require explicit macOS permission, run only while Needlbar is
running, and contain no credentials or raw provider data. They evaluate fresh
Claude/Codex quota observations only, use conservative at-most-once local
submission state, and do not apply to Cursor quota.

The native macOS 14 acceptance boundary is documented verbatim in the
Availability and Known limitations sections; it must not be hidden by the
feature summary.

### v0.2.2 local repository analytics

The analytics section must use this exact public heading and copy:

```markdown
## v0.2.2 local repository analytics

The feature is released and remains local-only; no analytics history is retained after the in-memory state is discarded.
```

Under that copy, explain that **Overview → Analytics…** opens a manual,
on-demand view over the fixed closed 30-day interval ending at capture time.
It uses only automatically observed local Claude, Codex, and Cursor workspaces
and reports repository totals, provider/model breakdowns, local commit rows,
optional local PR-number metadata, estimated cost, coverage, and **observed
active AI-session time**.

The explanation must state that observed active AI-session time is derived from
local session timestamps and is not human coding time, keyboard time, elapsed
wall time, or a productivity measure. It must also state that commit
association is deterministic local time-window metadata, not causal attribution
or measured commit cost; estimated cost is not an invoice or subscription
charge; and missing evidence remains visible as partial coverage or
Unattributed data rather than becoming zero.

Analytics is manual and local-only: no startup scan, timer, watcher, background
refresh, remote Git/forge request, provider authentication, network request,
backend, database, or analytics history. Analytics does not change the v0.2.0
export schema or v0.2.1 widget/notification behavior.

## 5. Provider support

State the fixed provider set plainly: Claude Code, Codex, and Cursor. A compact
table or subsections should cover:

- Claude usage from `~/.claude/projects` and `~/.claude/transcripts`, with quota
  available after provider-native sign-in and the approved explicit Keychain
  verification path.
- Codex usage from `~/.codex/sessions` and available archived sessions, with
  quota using existing provider authentication and its read-only fallback.
- Cursor usage from the existing compatible local cache at
  `~/.config/tokscale/cursor-cache/usage.csv`; Needlbar does not create or
  refresh that cache. Cursor quota is unavailable in Needlbar, and **Open
  Cursor Spending** opens the provider-owned dashboard.

Link the Claude, Codex, and Cursor runbooks for provider-local details. Do not
reintroduce superseded Cursor session-token, private endpoint, browser-cookie,
or remote-usage claims.

## 6. Privacy and local-first boundaries

Retain the product-level statement that Needlbar has no Needlbar account,
backend, hosted sync, cloud analytics service, or telemetry. It reads only the
documented local usage sources, and Claude/Codex quota requests go directly to
their providers when applicable. The README should say that Needlbar displays
normalized counts, estimated costs, quota percentages, reset timestamps,
freshness, and safe error states—not conversation or source content.

The Cursor boundary sentence is required verbatim:

```text
Needlbar does not use Cursor credentials, cookies, private endpoints, or remote usage hydration.
```

Also retain the practical exclusions: no upload of token history, prompts,
assistant responses, source code, raw paths, account identifiers, or provider
credentials; no raw provider responses or credentials in Swift state,
diagnostics, logs, or bridge errors; and no analytics database. Link
`docs/privacy.md` for the complete policy.

## 7. Development, known limitations, and documentation

Keep the development commands accurate and grouped for contributors:

```bash
git submodule update --init --recursive
source "$HOME/.cargo/env"  # when Rust was installed with rustup
make test
make run
make package
make smoke
```

Explain that `make test` is the project-wide verification command, while
`make package` and `make smoke` cover a local arm64 ad-hoc evaluation bundle.
Mention the Swift 6-compatible Xcode toolchain and Rust/Cargo requirements.
Keep release signing, notarization, stapling, and GitHub publication out of
the local development workflow.

Known limitations should be a short, user-relevant list:

- Apple Silicon (`arm64`) and macOS 14 or later are required for the public
  artifact; Intel packaging is not supported.
- Cursor quota is unavailable inside Needlbar; use **Open Cursor Spending**.
- Analytics is a manual, bounded local analysis with best-effort local Git/PR
  metadata and no retained history.
- The exact native macOS 14 Widget Gallery/App Group and notification-
  permission acceptance caveat remains as stated verbatim above.

Keep links to `docs/privacy.md`, `docs/architecture.md`, the three provider
runbooks, `SECURITY.md`, `CONTRIBUTING.md`, `AGENTS.md`, and the approved
specification/implementation-plan records. Link labels should describe the
reader benefit rather than expose maintainer chronology.

## 8. Errors, scope, and non-goals

This change edits only `README.md` in implementation. It must not modify
`docs/STATUS.md`, application source, release workflow, release artifacts,
provider behavior, or approved specs other than this design document.

The README must not add claims for:

- a Needlbar account, hosted service, telemetry, cloud sync, or remote
  analytics;
- Cursor quota retrieval, Cursor credential handling, private endpoint use, or
  remote usage hydration;
- analytics history, background refresh, remote forge/PR integration, causal
  attribution, measured productivity, or invoice-grade cost;
- widget/notification native acceptance that is not evidenced on macOS 14;
- a public artifact created by `make package`; or
- a historical tagless validation run being a public release.

If a linked file is absent or a required release string cannot be represented
without changing product meaning, stop and surface the discrepancy rather than
inventing a path or claim. Documentation errors should remain generic and
user-actionable; never paste raw command output, paths, credentials, or tokens
into the README.

## 9. Validation and acceptance

The README implementation is accepted only when all of the following pass:

1. Run the focused release/documentation contract:

   ```bash
   bash scripts/tests/notarize-app-tests.sh
   ```

   It must select the post-public phase from the exact
   `## v0.2.2 Public Release Record — 2026-09-01` heading in `docs/STATUS.md`,
   require the exact public availability/link/signing/analytics strings, and
   reject stale prepared, unreleased, or phase-mismatched wording plus missing
   Cursor/native-acceptance boundaries.

2. Verify the required release paths and local documentation links. The ZIP
   and sidecar URLs must use the exact `v0.2.2` release path and filenames;
   every relative Markdown link in `README.md` must resolve to a tracked file
   or directory from the repository root.

3. Run `git diff --check` and require a clean exit.

4. Perform a README-specific scan for stale headings/claims (`What v0.1
   does`, `v0.2.1 widgets and notifications (unreleased)`, prepared/future
   release wording, and prominent RC chronology), required exact strings,
   and the exact three-provider scope. This can be a focused shell/Ruby check;
   it must not become a new product test suite.

5. Do not run `make test` for this documentation-only change unless the
   focused release contract explicitly invokes it or a changed executable
   contract requires it. The release contract and link/path checks are the
   verification boundary for this work.

After the README refresh, the next product work is the v0.2.1 native macOS 14
arm64 Widget Gallery/App Group and notification acceptance. v0.3 is unplanned
until a new brainstorming/approval cycle; this README refresh must not imply a
v0.3 roadmap.

## 10. Approved references

- `docs/superpowers/specs/2026-08-13-needlbar-v0.1-design.md` — base product,
  provider, privacy, and architecture contract.
- `docs/superpowers/specs/2026-08-25-provider-managed-browser-login-design.md`
  — Claude/Codex provider-owned authentication UX.
- `docs/superpowers/specs/2026-08-26-cursor-local-usage-dashboard-quota-design.md`
  — Cursor local-cache and Spending-dashboard boundary.
- `docs/superpowers/specs/2026-08-29-needlbar-v0.2.0-local-json-export-design.md`
  — local snapshot export contract.
- `docs/superpowers/specs/2026-08-31-needlbar-v0.2.1-widgets-notifications-design.md`
  — widget, notification, and native-acceptance boundary.
- `docs/superpowers/specs/2026-09-01-needlbar-v0.2.2-local-repository-cost-analytics-design.md`
  — analytics scope and truthful terminology.
- `docs/superpowers/specs/2026-09-01-needlbar-v0.2.2-public-release-design.md`
  — exact public README phase and release-artifact contract.
- `scripts/tests/notarize-app-tests.sh` — executable release/documentation
  contract.
- `docs/STATUS.md` — current public release record and next continuation
  boundary; unchanged by this design.
