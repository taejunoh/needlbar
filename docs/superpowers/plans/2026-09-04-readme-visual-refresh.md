# README Visual Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the three README development-build screenshots with current, privacy-safe, native light-mode captures without changing the public v0.2.2 release contract.

**Architecture:** This is documentation work only. Package the exact development app, temporarily set only the approved system-monitor preferences in `com.taejunoh.needlbar`, and launch that exact bundle under an isolated provider home plus a no-network/no-`securityd` sandbox. Capture only the selected native Needlbar window, restore the complete defaults-domain export through canonical JSON equality, then commit only the README and three PNGs.

**Tech Stack:** Markdown, PNG, macOS `defaults`, `plutil`, `sandbox-exec`, `open`, `screencapture`, `sips`, SwiftPM/Cargo packaging, Git.

---

## File map and fixed boundaries

| Path | Role in this task |
| --- | --- |
| `README.md` | Replace only v0.3 development-dashboard/Settings image markup and concise captions. |
| `docs/images/system-dashboard.png` | Native light-mode dashboard capture at the real 312-point width. |
| `docs/images/settings-modules.png` | Native light-mode Settings capture at its upper scroll position. |
| `docs/images/settings-providers.png` | Native light-mode Settings capture at its lower scroll position. |
| `Sources/NeedlbarCore/Configuration/ModuleConfiguration.swift` | Read-only confirmation of the eleven persisted capture keys. |
| `Sources/Needlbar/App/AppDelegate.swift` | Read-only confirmation that `needlbar://overview` opens the dashboard. |
| `Sources/Needlbar/Settings/SettingsWindowController.swift` | Read-only confirmation of the native Settings title and no app-owned frame/appearance key. |
| `scripts/package-app.sh` and `scripts/verify-provider-brand-assets.sh` | Existing package and official-brand validation; do not edit. |

The implementation commit may contain only `README.md` and the three image paths
above. Do not modify application code, tests, scripts, build/release metadata,
`docs/STATUS.md`, specifications, or the public v0.2.2 artifact.

The established defaults domain is `com.taejunoh.needlbar`. The only temporary
settings are these eleven keys:

```text
needlbar.systemMonitor.order
needlbar.systemMonitor.visible
needlbar.systemMonitor.localIP
needlbar.systemMonitor.publicIP
needlbar.systemMonitor.ai.order
needlbar.systemMonitor.ai.claude.visible
needlbar.systemMonitor.ai.claude.metric
needlbar.systemMonitor.ai.codex.visible
needlbar.systemMonitor.ai.codex.metric
needlbar.systemMonitor.ai.cursor.visible
needlbar.systemMonitor.ai.cursor.metric
```

Use this exact temporary state: module order and visibility `cpu memory disk
network battery ai`; local/public IP `false`; provider order `claude codex
cursor`; every provider visible; every metric `remaining`. `SettingsWindowController`
does not persist a frame or appearance key. The capture root must be outside the
repository, under `/Users/taejunoh/Developer/LFG/`, and must never be committed.

### Task 1: Package safely and create a reversible capture state

**Files:**
- Verify: `Resources/Info.plist`, `Sources/NeedlbarCore/Configuration/ModuleConfiguration.swift`, `Sources/Needlbar/App/AppDelegate.swift`, `Sources/Needlbar/Settings/SettingsWindowController.swift`
- Create outside repository: `/Users/taejunoh/Developer/LFG/needlbar-readme-capture.XXXXXX/`

- [ ] **Step 1: Confirm the eligible bundle and documented settings facts.**

Run:
```bash
git status --short
plutil -extract CFBundleIdentifier raw -o - Resources/Info.plist
rg -n 'needlbar\.systemMonitor\.|needlbar://overview|Needlbar Settings|setFrameAutosaveName|AppleInterfaceStyle' \
  Sources/NeedlbarCore/Configuration/ModuleConfiguration.swift \
  Sources/Needlbar/App/AppDelegate.swift \
  Sources/Needlbar/Settings/SettingsWindowController.swift
```

Expected: the worktree has no implementation changes, the bundle identifier is
`com.taejunoh.needlbar`, the eleven listed keys and overview deep link exist,
and no Settings frame/appearance setting is introduced. Stop on any discrepancy;
do not guess a key or use a public/release app.

- [ ] **Step 2: Package the current development bundle but do not launch it.**

Run:
```bash
source /Users/taejunoh/.cargo/env
make package
CAPTURE_APP="$PWD/dist/Needlbar.app"
CAPTURE_EXECUTABLE="$CAPTURE_APP/Contents/MacOS/Needlbar"
test -x "$CAPTURE_EXECUTABLE"
plutil -extract CFBundleIdentifier raw -o - "$CAPTURE_APP/Contents/Info.plist" | grep -Fx com.taejunoh.needlbar
codesign --verify --deep --strict "$CAPTURE_APP"
./scripts/verify-provider-brand-assets.sh "$CAPTURE_APP/Contents/Resources/Needlbar_NeedlbarApp.bundle/ProviderBrands"
```

Expected: every command exits zero. `CAPTURE_APP` is the only app eligible for
this task; never use `/Applications/Needlbar.app`, a release ZIP, or an
acceptance fixture app.

- [ ] **Step 3: Snapshot the whole defaults domain and light-appearance state outside the repository.**

Run:
```bash
umask 077
CAPTURE_ROOT="$(mktemp -d /Users/taejunoh/Developer/LFG/needlbar-readme-capture.XXXXXX)"
defaults export com.taejunoh.needlbar "$CAPTURE_ROOT/needlbar-before.plist"
plutil -convert json -o "$CAPTURE_ROOT/needlbar-before.json" "$CAPTURE_ROOT/needlbar-before.plist"
if defaults read -g AppleInterfaceStyle > "$CAPTURE_ROOT/appearance-before.txt" 2>/dev/null; then
  printf present > "$CAPTURE_ROOT/appearance-state.txt"
else
  printf absent > "$CAPTURE_ROOT/appearance-state.txt"
  : > "$CAPTURE_ROOT/appearance-before.txt"
fi
mkdir -p "$CAPTURE_ROOT/home/.claude" "$CAPTURE_ROOT/home/.codex" \
  "$CAPTURE_ROOT/home/.config/tokscale/cursor-cache"
```

Expected: the capture root is mode-private, lies outside the repository, has a
whole-domain backup and a canonical JSON representation, and has empty provider
roots. Never print, commit, or include these files in screenshots.

- [ ] **Step 4: Apply only the approved temporary dashboard state.**

Run:
```bash
defaults write com.taejunoh.needlbar needlbar.systemMonitor.order -array cpu memory disk network battery ai
defaults write com.taejunoh.needlbar needlbar.systemMonitor.visible -array cpu memory disk network battery ai
defaults write com.taejunoh.needlbar needlbar.systemMonitor.localIP -bool false
defaults write com.taejunoh.needlbar needlbar.systemMonitor.publicIP -bool false
defaults write com.taejunoh.needlbar needlbar.systemMonitor.ai.order -array claude codex cursor
for PROVIDER in claude codex cursor; do
  defaults write com.taejunoh.needlbar "needlbar.systemMonitor.ai.${PROVIDER}.visible" -bool true
  defaults write com.taejunoh.needlbar "needlbar.systemMonitor.ai.${PROVIDER}.metric" -string remaining
done
defaults delete -g AppleInterfaceStyle 2>/dev/null || true
```

Expected: the next launch is light, has the six requested modules and all three
providers in order, and displays neither local nor public IP. Do not touch
notifications, exports, sign-in, refresh, spending, Keychain, or a provider UI.

- [ ] **Step 5: Define the exact no-provider/no-network launch boundary.**

Run:
```bash
CAPTURE_PROFILE='(version 1) (allow default) (deny network*) (deny mach-lookup (global-name "com.apple.securityd"))'
ps -axo pid=,command= | rg '/Applications/Needlbar\.app/Contents/MacOS/Needlbar' && exit 1 || true
```

Expected: the public app is not running and the inline sandbox policy denies
all network and direct `securityd` access. The launch in Task 2 must set
`HOME`, `CLAUDE_CONFIG_DIR`, and `CODEX_HOME` to the empty capture roots as a
separate boundary. Do not create a capture helper, app code, or repository script.

### Task 2: Capture only the three native Needlbar windows

**Files:**
- Create outside repository: `$CAPTURE_ROOT/*.native.png`, temporary logs, and window identifiers
- Replace after approval: `docs/images/system-dashboard.png`, `docs/images/settings-modules.png`, `docs/images/settings-providers.png`

- [ ] **Step 1: Start the exact packaged app under the isolated environment and prove its identity.**

Run:
```bash
HOME="$CAPTURE_ROOT/home" \
CLAUDE_CONFIG_DIR="$CAPTURE_ROOT/home/.claude" \
CODEX_HOME="$CAPTURE_ROOT/home/.codex" \
sandbox-exec -p "$CAPTURE_PROFILE" "$CAPTURE_EXECUTABLE" > "$CAPTURE_ROOT/app.log" 2>&1 &
CAPTURE_PID=$!
sleep 1
ps -p "$CAPTURE_PID" -o pid= -o command= | grep -F "$CAPTURE_EXECUTABLE"
```

Expected: exactly one current `CAPTURE_PID` executes the packaged development
binary. If it exits or its command is different, restore Task 1's snapshots and
stop. Do not launch an unsandboxed replacement.

- [ ] **Step 2: Open the dashboard through the approved deep link and capture its one native window.**

Run:
```bash
open -gj -a "$CAPTURE_APP" needlbar://overview
sleep 1
screencapture -x -o -i -w "$CAPTURE_ROOT/system-dashboard.native.png"
sips -g pixelWidth -g pixelHeight -g hasAlpha "$CAPTURE_ROOT/system-dashboard.native.png"
```

When the native window picker appears, select only the currently visible
Needlbar dashboard window belonging to `CAPTURE_PID`; never select the desktop,
browser, terminal, public app, or any other window. Retain the image only if it
is an app-window-only capture with a 624-pixel width on the current 2x display
(the actual 312-point dashboard width), light appearance, CPU → RAM → Disk →
Network → Battery → AI usage order, Claude/Codex/Cursor rows, official Claude,
OpenAI Blossom/Codex, and Cursor assets, centered provider title/icon pairs,
and no local/public IP value. If any check fails, discard the candidate outside
the repository and stop; do not crop, stretch, synthesize, or change app code.

- [ ] **Step 3: Capture the upper and lower positions of the same Settings window.**

Click only the dashboard footer **Settings** button. Do not click Analytics,
provider sign-in, spending, refresh, export, notifications, pickers, or any
provider action. At the upper position run:

```bash
screencapture -x -o -i -w "$CAPTURE_ROOT/settings-modules.native.png"
sips -g pixelWidth -g pixelHeight -g hasAlpha "$CAPTURE_ROOT/settings-modules.native.png"
```

Select only the native **Needlbar Settings** window owned by `CAPTURE_PID`. Keep
the result only if it is light, app-only, shows module visibility/order and both
local/public IP controls off, and contains no path, account, credential, or IP.
Scroll that same window down without changing a control, then run:

```bash
screencapture -x -o -i -w "$CAPTURE_ROOT/settings-providers.native.png"
sips -g pixelWidth -g pixelHeight -g hasAlpha "$CAPTURE_ROOT/settings-providers.native.png"
```

Select the same Settings window. Keep the lower image only if Claude → Codex →
Cursor visibility/order, `Remaining` selections, provider actions, official
provider art, and centered provider-title pairs are readable. Do not combine
multiple crops into a synthetic Settings image. If the UI cannot expose these
groups safely in one native window position, stop and report the constraint.

- [ ] **Step 4: Perform privacy, geometry, and native-scope review before copying images.**

Run:
```bash
for IMAGE in "$CAPTURE_ROOT"/*.native.png; do
  file "$IMAGE"
  sips -g pixelWidth -g pixelHeight -g hasAlpha "$IMAGE"
  shasum -a 256 "$IMAGE"
done
```

At 100% size, inspect all three candidates. Reject any capture containing an
IPv4/IPv6 address, credential, account identifier, local path, terminal/browser
content, desktop background, raw provider payload, or non-light rendering.
The dashboard's 624-pixel/312-point geometry, all required rows, and native
window border/shadow must be intact. The Settings images retain their native
width and are never resized. OCR is optional support only; visual review is
the acceptance authority. After all checks pass, copy the three approved files:

```bash
cp "$CAPTURE_ROOT/system-dashboard.native.png" docs/images/system-dashboard.png
cp "$CAPTURE_ROOT/settings-modules.native.png" docs/images/settings-modules.png
cp "$CAPTURE_ROOT/settings-providers.native.png" docs/images/settings-providers.png
```

- [ ] **Step 5: Stop only the proven capture process and restore the exact settings snapshot.**

Run:
```bash
ps -p "$CAPTURE_PID" -o command= | grep -F "$CAPTURE_EXECUTABLE"
kill -TERM "$CAPTURE_PID"
for _ in $(seq 1 50); do kill -0 "$CAPTURE_PID" 2>/dev/null || break; sleep 0.1; done
! kill -0 "$CAPTURE_PID" 2>/dev/null
defaults import com.taejunoh.needlbar "$CAPTURE_ROOT/needlbar-before.plist"
if [ "$(cat "$CAPTURE_ROOT/appearance-state.txt")" = present ]; then
  defaults write -g AppleInterfaceStyle "$(cat "$CAPTURE_ROOT/appearance-before.txt")"
else
  defaults delete -g AppleInterfaceStyle 2>/dev/null || true
fi
defaults export com.taejunoh.needlbar "$CAPTURE_ROOT/needlbar-after.plist"
plutil -convert json -o "$CAPTURE_ROOT/needlbar-after.json" "$CAPTURE_ROOT/needlbar-after.plist"
cmp "$CAPTURE_ROOT/needlbar-before.json" "$CAPTURE_ROOT/needlbar-after.json"
```

Expected: only the exact capture PID stops; the complete domain's canonical JSON
is byte-identical before/after; global appearance presence/value is restored.
On any mismatch, stop and report it before editing the README or making a commit.

### Task 3: Update the README and commit only the approved visual refresh

**Files:**

- Modify: `README.md`
- Add/replace: `docs/images/system-dashboard.png`, `docs/images/settings-modules.png`, `docs/images/settings-providers.png`
- Verify: `scripts/tests/notarize-app-tests.sh`

- [ ] **Step 1: Replace only the approved screenshot markup and captions.**

In `### System monitor (v0.3 development build)`, use exactly:

```markdown
<img src="docs/images/system-dashboard.png" alt="Needlbar development dashboard showing CPU, RAM, Disk, Network, Battery, and Claude, Codex, and Cursor AI usage with IP values hidden" width="312" />

*Development build, not the public v0.2.2 artifact: values are native examples, provider visibility is configurable, and IP values are omitted.*
```

Immediately after the remaining-quota explanation, add exactly:

```markdown
The dashboard uses the official Claude, OpenAI Blossom/Codex, and Cursor icons with centered provider-title alignment.
```

In `### Settings (v0.3 development build)`, use exactly:

```markdown
<img src="docs/images/settings-modules.png" alt="Needlbar development Settings showing dashboard module visibility and disabled local and public IP controls" width="520" />

<img src="docs/images/settings-providers.png" alt="Needlbar development Settings showing Claude, Codex, and Cursor visibility, order, Remaining selections, and provider actions" width="520" />

*Same development Settings window at upper and lower scroll positions; module and provider display controls are configurable, all provider rows use Remaining for this capture, and local/public IP display is off.*
```

Keep the public v0.2.2 download/checksum, signing/notarization, installation,
local-package disclaimer, macOS 14 caveat, provider/privacy/analytics sections,
and section order. Do not claim v0.3 is publicly released or add login, Keychain,
provider-refresh, public-IP, telemetry, hosted-service, or acceptance claims.

- [ ] **Step 2: Validate links, privacy, image geometry, release wording, and scope.**

Run:
```bash
bash scripts/tests/notarize-app-tests.sh
rg -n 'Needlbar v0\.2\.2|Needlbar-macos-arm64\.zip|notarized|macOS 14|System monitor \(v0\.3 development build\)|Development build, not the public v0\.2\.2 artifact|official Claude, OpenAI Blossom/Codex, and Cursor icons|settings-modules\.png|settings-providers\.png|width="312"|width="520"' README.md
! rg -n '(?:\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b)|(?:\b[0-9A-Fa-f]{1,4}:[0-9A-Fa-f:]+\b)|needlbar-readme-capture' README.md
for IMAGE in docs/images/system-dashboard.png docs/images/settings-modules.png docs/images/settings-providers.png; do
  file "$IMAGE"
  sips -g pixelWidth -g pixelHeight -g hasAlpha "$IMAGE"
done
test "$(sips -g pixelWidth docs/images/system-dashboard.png | awk '/pixelWidth/ { print $2 }')" = 624
git diff --check
git diff --name-only HEAD
```

Expected: the release-documentation contract passes; all three PNGs are valid
and referenced; dashboard image width is 624 native pixels (312 points); no
address or capture-root string enters README; and the only changed paths are
the README plus the three approved PNGs.

- [ ] **Step 3: Review the exact diff and make the documentation-only commit.**

Run:
```bash
git diff -- README.md
git diff --stat -- README.md docs/images/system-dashboard.png docs/images/settings-modules.png docs/images/settings-providers.png
git diff --check
git add README.md docs/images/system-dashboard.png docs/images/settings-modules.png docs/images/settings-providers.png
git commit -m "docs: refresh development dashboard visuals"
git status --short
```

Expected: one focused commit contains exactly the README plus its three native
images. Do not push, merge, release, sign, notarize, or retain capture-root data.

## Final acceptance checklist

- [ ] Exact packaged development app ran under isolated `HOME`, `CLAUDE_CONFIG_DIR`, and `CODEX_HOME`, with network and `securityd` denied.
- [ ] All three captures are selected app-window-only Needlbar windows for the verified capture PID; none is a desktop, release app, fixture, or synthetic image.
- [ ] The dashboard is native light mode at 312 points, includes all six sections and three provider rows, and has no local/public IP value.
- [ ] The upper/lower Settings images are native light captures of the same current Settings UI and show their required controls.
- [ ] Official provider art and centered icon/title alignment are visible wherever provider rows appear; the images contain no sensitive data.
- [ ] Whole-domain defaults canonical JSON and global appearance presence/value are restored before README editing.
- [ ] The public v0.2.2 boundary and native macOS 14 caveat remain explicit; `bash scripts/tests/notarize-app-tests.sh` and `git diff --check` pass.
