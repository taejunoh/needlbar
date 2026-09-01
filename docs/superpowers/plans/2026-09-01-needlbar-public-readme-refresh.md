# Needlbar Public-Facing README Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Rewrite README.md into a concise, current-state guide for the public Needlbar v0.2.2 release, installation, features, provider boundaries, privacy, development, and known limitations.

**Architecture:** This is documentation-only. Edit README.md only; use the existing scripts/tests/notarize-app-tests.sh plus a one-off shell/Ruby check as the verification boundary, with docs/STATUS.md remaining the public-release source of truth.

**Tech Stack:** Markdown, Bash, Ruby, GitHub Release links, Git.

---

## File and Responsibility Map

| File | Responsibility |
| --- | --- |
| README.md | The only implementation file: public-release documentation and user-facing product boundaries. |
| scripts/tests/notarize-app-tests.sh | Existing executable release/documentation contract; verification-only and not to be edited unless a genuine diagnostic defect appears. |
| docs/STATUS.md | Unchanged public v0.2.2 release record and next continuation boundary. |
| docs/superpowers/specs/2026-09-01-needlbar-readme-public-refresh-design.md | Approved ordering, exact content, non-goals, and acceptance contract. |

Do not modify product code, release workflows/artifacts, docs/STATUS.md, approved specs, or test scripts.

### Task 1: Rewrite README around the current public release

**Files:**
- Modify: README.md

- [ ] **Step 1: Confirm the public phase and link targets before editing.**

Run:

~~~bash
grep -Fx '## v0.2.2 Public Release Record — 2026-09-01' docs/STATUS.md
git ls-files README.md docs/privacy.md docs/architecture.md docs/providers/claude.md docs/providers/codex.md docs/providers/cursor.md SECURITY.md CONTRIBUTING.md AGENTS.md docs/STATUS.md docs/superpowers/specs/2026-08-13-needlbar-v0.1-design.md docs/superpowers/plans/2026-08-13-needlbar-v0.1.md
~~~

Expected: the exact public-record heading is present and every intended local README link target is tracked. If a required file is absent, stop and report the discrepancy instead of inventing a path or claim.

- [ ] **Step 2: Rewrite the README using the required section order and exact release strings.**

Keep # Needlbar first, followed by these top-level headings in this order:

~~~text
## Availability and download
## Current features
## v0.2.2 local repository analytics
## Provider support
## Privacy and local-first boundaries
## Development
## Known limitations and documentation
## Credits and licenses
~~~

The introduction is one short product description and one short local-first paragraph: Needlbar is a native macOS menu-bar monitor for Claude Code, Codex, and Cursor showing locally aggregated token usage, estimated cost, quota windows, and reset times; it has no Needlbar account, backend, hosted sync, cloud analytics service, or telemetry.

Availability must include these exact strings:

~~~text
Needlbar v0.2.2 is publicly available for macOS 14 or later on Apple Silicon.
The public artifact is Developer ID-signed and notarized.
The local package is ad-hoc signed and is not a substitute for the public artifact.
Native signed macOS 14 arm64 Widget Gallery/App Group and notification-permission acceptance still require external evidence; the local macOS 26 build is not that acceptance.
~~~

Include these exact direct links:

~~~markdown
[Download Needlbar v0.2.2 for Apple Silicon](https://github.com/taejunoh/needlbar/releases/download/v0.2.2/Needlbar-macos-arm64.zip)
[Download the SHA-256 checksum](https://github.com/taejunoh/needlbar/releases/download/v0.2.2/Needlbar-macos-arm64.zip.sha256)
~~~

Explain that Needlbar-macos-arm64.zip.sha256 is the ZIP SHA-256 checksum sidecar and show:

~~~bash
shasum -a 256 -c Needlbar-macos-arm64.zip.sha256
~~~

Give four short installation steps: download both files from the v0.2.2 GitHub Release; run the command from the directory containing both files; open the verified ZIP and drag Needlbar.app into /Applications; launch it from /Applications so it appears in the menu bar. Explain that make package creates only a local Apple-Silicon evaluation bundle and is not the public artifact. Retain one brief sentence containing the word tagless explaining protected tagless validation is historical/pre-release evidence and not a public download; omit run IDs, RC chronology, and a prominent maintainer-only history section.

Under ## Current features, use capability groups rather than release-milestone headings:

- ### Usage and quota monitoring: Overview shows today’s combined tokens/cost, the most constrained eligible quota, a seven-day chart, provider status, and Settings. Provider modules show today’s usage/cost, input/output/cache tokens, quota/reset details, freshness, and safe recovery. Usage and quota are independent streams, so one failure never replaces a last-known-good value with zero. Settings controls modules/title metrics; Claude and Codex use provider-owned claude auth login --claudeai and codex login browser flows; Needlbar has no second OAuth flow; Cursor has no Needlbar credential/connection workflow.
- ### Local snapshot export: Export snapshot… is a user-initiated JSON export of the current normalized snapshot. It does not refresh, authenticate, access Keychain, or upload; it contains only approved normalized usage/quota/freshness/safe-status fields and excludes credentials, account identifiers, raw paths/responses, prompts, assistant responses, source code, and raw diagnostics.
- ### Widget and quota notifications: The released app includes one medium Overview widget backed by a sanitized local projection; it does not refresh providers. Notifications are off by default, require explicit macOS permission, run only while Needlbar runs, contain no credentials/raw provider data, evaluate fresh Claude/Codex quota only with conservative at-most-once state, and do not apply to Cursor quota. Keep the native macOS 14 caveat visible in Availability and Known limitations.

The analytics heading must be exactly ## v0.2.2 local repository analytics and immediately contain this exact sentence:

~~~text
The feature is released and remains local-only; no analytics history is retained after the in-memory state is discarded.
~~~

Explain Overview → Analytics… as a manual, on-demand fixed closed 30-day analysis ending at capture time over automatically observed local Claude, Codex, and Cursor workspaces. State that it reports repository totals, provider/model breakdowns, local commit rows, optional local PR-number metadata, estimated cost, coverage, and observed active AI-session time. State that active-session time comes from local session timestamps and is not human coding time, keyboard time, elapsed wall time, or a productivity measure; commit association is deterministic local time-window metadata, not causal attribution or measured commit cost; estimated cost is not an invoice or subscription charge; and missing evidence remains partial coverage or Unattributed instead of becoming zero. State that analytics has no startup scan, timer, watcher, background refresh, remote Git/forge request, provider authentication, network request, backend, database, or retained history, and does not change the v0.2.0 export schema or v0.2.1 widget/notification behavior.

- [ ] **Step 3: Complete provider, privacy, development, limitations, documentation, and license sections.**

Under ## Provider support, state the fixed provider set plainly: Claude Code, Codex, and Cursor. Include these source/quota boundaries:

- Claude: ~/.claude/projects and ~/.claude/transcripts; quota after provider-native sign-in and approved explicit Keychain verification.
- Codex: ~/.codex/sessions and available archived sessions; quota uses existing provider authentication and its read-only fallback.
- Cursor: existing compatible ~/.config/tokscale/cursor-cache/usage.csv; Needlbar does not create or refresh it, Cursor quota is unavailable, and Open Cursor Spending opens the provider-owned dashboard.

Link the Claude, Codex, and Cursor runbooks. Do not reintroduce Cursor session-token, private-endpoint, browser-cookie, or remote-usage claims.

Under ## Privacy and local-first boundaries, retain no Needlbar account/backend/hosted sync/cloud analytics/telemetry, local-source reads, direct Claude/Codex provider quota requests when applicable, and normalized counts/costs/quota percentages/reset timestamps/freshness/safe errors—not conversation or source content. Include this sentence verbatim:

~~~text
Needlbar does not use Cursor credentials, cookies, private endpoints, or remote usage hydration.
~~~

Also state that token history, prompts, assistant responses, source code, raw paths, account identifiers, and provider credentials are never uploaded; raw provider responses and credentials stay out of Swift state, diagnostics, logs, and bridge errors; and Analytics has no database. Link docs/privacy.md.

Under ## Development, use this exact command block:

~~~bash
git submodule update --init --recursive
source "$HOME/.cargo/env"  # when Rust was installed with rustup
make test
make run
make package
make smoke
~~~

Explain that make test is project-wide verification; make package and make smoke cover a local arm64 ad-hoc evaluation bundle; Swift 6-compatible Xcode and Rust/Cargo are required; and local development does not perform release signing, notarization, stapling, or GitHub publication.

Under ## Known limitations and documentation, list: public artifact requires Apple Silicon (arm64) and macOS 14 or later and Intel packaging is unsupported; Cursor quota is unavailable and uses Open Cursor Spending; Analytics is manual, bounded, local-only, best-effort for local Git/PR metadata, and retains no history; and the exact native macOS 14 caveat. Link docs/privacy.md, docs/architecture.md, all three provider runbooks, SECURITY.md, CONTRIBUTING.md, AGENTS.md, docs/STATUS.md, and the approved specification/implementation-plan records with reader-benefit labels. Use this concrete credits content under ## Credits and licenses: Needlbar embeds the pinned Tokscale/tokscale-core usage engine, states its Copyright (c) 2025 Junho Yeo and MIT license, links vendor/tokscale-core/LICENSE and the packaged ThirdPartyNotices.txt, then states that Needlbar-owned source is MIT-licensed and links LICENSE.

The finished README must not contain ## What v0.1 does, ## v0.2.1 widgets and notifications (unreleased), prepared/future public-release wording, Needlbar is currently unreleased., a no-public-download claim, run IDs, RC chronology, or unsupported Widget Gallery/App Group/notification acceptance. Do not add a v0.3 roadmap or unsupported account/cloud/Cursor-quota/remote-analytics/productivity/invoice-grade-cost/public-local-package claim.

### Task 2: Validate the README contract and commit the implementation

**Files:**
- Verify: scripts/tests/notarize-app-tests.sh
- Verify: tracked README links and README text with one-off shell/Ruby commands
- Modify: README.md only

- [ ] **Step 1: Run the focused executable release/documentation contract.**

Run:

~~~bash
bash scripts/tests/notarize-app-tests.sh
~~~

Expected: exit status 0 and final output notarize-app shell contracts passed. It must select the post-public phase from ## v0.2.2 Public Release Record — 2026-09-01, require exact public availability/download/signing/analytics strings, and reject stale phase wording and missing Cursor/native-acceptance boundaries. Do not edit the script merely to make README content pass; no script change is expected.

- [ ] **Step 2: Run a one-off README-specific exact-string, stale-claim, URL, provider-scope, and link-resolution check.**

Run this from the repository root without creating a test file:

~~~bash
ruby <<'RUBY'
require "pathname"

readme = File.read("README.md")
required = [
  "Needlbar v0.2.2 is publicly available for macOS 14 or later on Apple Silicon.",
  "[Download Needlbar v0.2.2 for Apple Silicon](https://github.com/taejunoh/needlbar/releases/download/v0.2.2/Needlbar-macos-arm64.zip)",
  "[Download the SHA-256 checksum](https://github.com/taejunoh/needlbar/releases/download/v0.2.2/Needlbar-macos-arm64.zip.sha256)",
  "shasum -a 256 -c Needlbar-macos-arm64.zip.sha256",
  "The public artifact is Developer ID-signed and notarized.",
  "The local package is ad-hoc signed and is not a substitute for the public artifact.",
  "Native signed macOS 14 arm64 Widget Gallery/App Group and notification-permission acceptance still require external evidence; the local macOS 26 build is not that acceptance.",
  "## v0.2.2 local repository analytics",
  "The feature is released and remains local-only; no analytics history is retained after the in-memory state is discarded.",
  "Needlbar does not use Cursor credentials, cookies, private endpoints, or remote usage hydration."
]
required.each { |text| abort "missing required README text: #{text}" unless readme.include?(text) }

forbidden = [
  "## What v0.1 does",
  "## v0.2.1 widgets and notifications (unreleased)",
  "Needlbar is currently unreleased.",
  "No public GitHub Release or notarized download is available yet.",
  "prepared for public release",
  "future public artifact",
  "33524771615",
  "33526409582",
  "tagless RC"
]
forbidden.each { |text| abort "stale or disallowed README text: #{text}" if readme.include?(text) }

expected_headings = [
  "## Availability and download", "## Current features", "## v0.2.2 local repository analytics",
  "## Provider support", "## Privacy and local-first boundaries", "## Development",
  "## Known limitations and documentation", "## Credits and licenses"
]
actual_headings = readme.lines.grep(/^## /).map(&:chomp)
abort "README top-level section order is incorrect" unless actual_headings == expected_headings

providers = readme.scan(/Claude Code|Codex|Cursor/).uniq.sort
abort "README must name exactly Claude Code, Codex, and Cursor" unless providers == ["Claude Code", "Codex", "Cursor"]
unsupported_providers = readme.scan(/\b(?:OpenAI|Gemini|Copilot|Aider|Windsurf)\b/).uniq
abort "README names unsupported provider(s): #{unsupported_providers.join(', ')}" unless unsupported_providers.empty?

links = readme.scan(/\[[^\]]+\]\(([^)]+)\)/).flatten
tracked = IO.popen(["git", "ls-files"], &:read).lines.map(&:chomp).to_h { |path| [path, true] }
links.each do |target|
  next if target.start_with?("http://", "https://", "#")
  relative = target.split("#", 2).first
  resolved = Pathname(relative).cleanpath
  abort "README relative link does not resolve: #{target}" unless File.file?(resolved) || File.directory?(resolved)
  abort "README relative link target is not tracked: #{target}" unless tracked.key?(resolved.to_s) || tracked.keys.any? { |entry| entry.start_with?("#{resolved}/") }
end

puts "README public-refresh contract passed"
RUBY
~~~

Expected: README public-refresh contract passed and exit status 0. This check covers exact ZIP/sidecar URLs, required strings, forbidden stale headings/claims, exact three-provider scope, and every relative Markdown link resolving to a tracked file or directory.

- [ ] **Step 3: Check whitespace and inspect the diff.**

Run:

~~~bash
git diff --check
git diff -- README.md
git status --short
~~~

Expected: git diff --check exits 0; only the intentional README rewrite is changed, in the required order, with no changes to STATUS, scripts, product code, workflows, artifacts, or approved specs. Do not run make test: the focused release contract and README-specific check are the approved boundary for this documentation-only change.

- [ ] **Step 4: Commit only the README implementation.**

Run:

~~~bash
git add README.md
git commit -m "docs: refresh README for v0.2.2"
~~~

Expected: one commit named docs: refresh README for v0.2.2 containing only README.md; do not push, tag, create/edit a GitHub Release, or modify release artifacts.

## Handoff after implementation

Report explicitly: the next product work is v0.2.1 native macOS 14 arm64 Widget Gallery/App Group and notification acceptance; v0.3 is unplanned until a new brainstorming/approval cycle. Do not add a v0.3 roadmap to README.

## Self-review checklist

- [ ] Every requirement and exact string in the approved README refresh spec is represented above.
- [ ] Every step names its path, command, and expected result; no unspecified content is left for the implementer.
- [ ] README.md is the only implementation file and the release shell contract is verification-only.
- [ ] The public phase is selected from the exact STATUS heading; tagless evidence is never presented as a release.
- [ ] No stale prepared/future wording or unsupported v0.3 roadmap is introduced.
