# Provider brand icons Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Needlbar’s current AI-provider SF Symbols with verified official Claude, OpenAI Blossom, and Cursor 2D marks without changing provider labels, values, actions, state, accessibility, or adaptive dashboard behavior.

**Architecture:** A single `ProviderBrandIcon` SwiftUI component in `NeedlbarApp` maps `ProviderID` to a fixed bundled resource, treatment, accessibility policy, and existing SF Symbol fallback. SwiftPM copies the unmodified provider-resource directory into its generated `Needlbar_NeedlbarApp.bundle`; package copies that bundle and the same offline manifest verifier runs against source and packaged resources.

**Tech Stack:** Swift 6, SwiftUI, AppKit, OSLog, Swift Testing, SwiftPM resources, Bash, PlistBuddy/plutil, shasum, file, and current Make package/smoke gates.

---

## Scope and execution rules

Read `AGENTS.md`, `docs/STATUS.md`, `docs/superpowers/specs/2026-09-04-provider-brand-icons-design.md`, and this plan before implementation. Work in a new isolated worktree under `/Users/taejunoh/Developer/LFG/needlbar/.worktrees/`. Do not modify the parent checkout’s pre-existing `vendor/tokscale-core`, `.logs/`, or `.superpowers/brainstorm/` state, and do not revert work from other agents.

Source Cargo before every Make command:

```bash
source /Users/taejunoh/.cargo/env
```

Only the maintainer’s asset-acquisition step may access a provider distribution. App runtime, test, package, smoke, and native verification must use committed local files only. Do not add a provider, API, credential/cookie read, remote download, browser/web view, persistence migration, provider data change, widget, notification, export, analytics, menu-bar behavior, signing, or release change.

Use only these official sources:

- Claude orange mark — Anthropic Official Brand Assets: `https://brandfolder.com/anthropic/collection/newsroom`.
- OpenAI Blossom — OpenAI Design: `https://openai.com/brand/`.
- Cursor 2D mark — Cursor Brand Guidelines: `https://cursor.com/en-US/brand`.

If the exact asset or its permitted use cannot be confirmed, stop before adding an asset, document the blocker in `docs/STATUS.md`, and request maintainer direction. Never substitute an icon-library image, search result, screenshot, generated asset, or redraw.

| Provider | Label | Resource ID | Rendering | Existing fallback |
| --- | --- | --- | --- | --- |
| Claude | `Claude` | `provider-brand-claude` | official orange / original | `sparkles` |
| Codex | `Codex` | `provider-brand-openai-blossom` | system monochrome / template | `chevron.left.forwardslash.chevron.right` |
| Cursor | `Cursor` | `provider-brand-cursor-2d` | system monochrome / template | `cursorarrow` |

All icons use an optically centered 18 × 18-point `.scaledToFit()` frame. Do not crop, stretch, redraw, recolor, or choose an asset from value/state. Fable is a Claude subordinate and gets no icon. Existing provider text remains; all current rows use a decorative icon so VoiceOver announces provider identity once from the text.

Required surfaces are precisely: System Dashboard AI Usage, Overview, provider detail, System Monitor Settings provider display, and Settings Connections. Preserve 312-point width, adaptive height, anchor, scrolling, outside-click dismissal, values, provider order/visibility, freshness/authentication, Fable, and login/Cursor-Spending actions.

## File map

| File | Responsibility |
| --- | --- |
| `Package.swift` | Copy unmodified app resources into `Bundle.module`. |
| `Sources/Needlbar/Resources/ProviderBrands/provider-brand-claude.png` | Unmodified official orange Claude PNG. |
| `Sources/Needlbar/Resources/ProviderBrands/provider-brand-openai-blossom.png` | Unmodified official monochrome Blossom PNG. |
| `Sources/Needlbar/Resources/ProviderBrands/provider-brand-cursor-2d.png` | Unmodified official Cursor 2D PNG. |
| `Sources/Needlbar/Resources/ProviderBrands/ProviderBrandAssets.plist` | Resource ID, provider, file, source/variant, type, rendering, fallback symbol, and SHA-256 manifest. |
| `Sources/Needlbar/Resources/ProviderBrands/TRADEMARKS.md` | Provider ownership and non-affiliation note. |
| `Sources/Needlbar/ProviderBrandIcon.swift` | Sole mapping, rendering, accessibility, fallback, and safe diagnostic owner. |
| Five approved current SwiftUI view files | Replace only leading provider glyphs. |
| `Tests/NeedlbarTests/ProviderBrandIconTests.swift` | Component mapping, size/aspect, light/dark rendering, local bundle, fallback, accessibility. |
| `Tests/NeedlbarTests/ProviderBrandSurfaceContractTests.swift` | Five-surface usage plus data/action/sizing regressions. |
| `scripts/verify-provider-brand-assets.sh` | Offline resource verifier. |
| `scripts/tests/provider-brand-assets-tests.sh` | Valid and malformed resource fixtures. |
| `scripts/package-app.sh`, `scripts/smoke-app.sh`, `scripts/tests/package-app-tests.sh`, `Makefile` | Package and smoke the same resource bundle. |
| `docs/STATUS.md` | Final evidence-only checkpoint. |

### Task 1: Add official assets, provenance, and offline integrity checks

**Files:**

- Modify: `Package.swift`
- Create: `Sources/Needlbar/Resources/ProviderBrands/provider-brand-claude.png`
- Create: `Sources/Needlbar/Resources/ProviderBrands/provider-brand-openai-blossom.png`
- Create: `Sources/Needlbar/Resources/ProviderBrands/provider-brand-cursor-2d.png`
- Create: `Sources/Needlbar/Resources/ProviderBrands/ProviderBrandAssets.plist`
- Create: `Sources/Needlbar/Resources/ProviderBrands/TRADEMARKS.md`
- Create: `scripts/verify-provider-brand-assets.sh`
- Create: `scripts/tests/provider-brand-assets-tests.sh`
- Modify: `Makefile`

- [ ] **Step 1: Write the failing verifier fixture test.**

Create `scripts/tests/provider-brand-assets-tests.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VERIFY="$ROOT/scripts/verify-provider-brand-assets.sh"
fixture="/tmp/needlbar-provider-brands-$RANDOM"
trap 'rm -rf -- "$fixture"' EXIT
fail() { echo "provider-brand-assets-tests: $*" >&2; exit 1; }
copy_fixture() {
  mkdir -p "$fixture/ProviderBrands"
  cp "$ROOT/Sources/Needlbar/Resources/ProviderBrands/ProviderBrandAssets.plist" "$fixture/ProviderBrands/"
  cp "$ROOT/Sources/Needlbar/Resources/ProviderBrands/TRADEMARKS.md" "$fixture/ProviderBrands/"
  cp "$ROOT/Sources/Needlbar/Resources/ProviderBrands/"provider-brand-*.png "$fixture/ProviderBrands/"
}
expect_failure() {
  local expected="$1"; shift
  local output status
  set +e; output="$("$@" 2>&1)"; status=$?; set -e
  [[ "$status" -ne 0 ]] || fail "expected failure: $expected"
  [[ "$output" == *"$expected"* ]] || fail "unexpected failure: $output"
}
copy_fixture; "$VERIFY" "$fixture/ProviderBrands"
rm "$fixture/ProviderBrands/provider-brand-cursor-2d.png"
expect_failure 'missing declared resource: provider-brand-cursor-2d' "$VERIFY" "$fixture/ProviderBrands"
rm -rf "$fixture/ProviderBrands"; copy_fixture; : > "$fixture/ProviderBrands/provider-brand-claude.png"
expect_failure 'empty declared resource: provider-brand-claude' "$VERIFY" "$fixture/ProviderBrands"
rm -rf "$fixture/ProviderBrands"; copy_fixture; printf 'not png\n' > "$fixture/ProviderBrands/provider-brand-openai-blossom.png"
expect_failure 'wrong image type: provider-brand-openai-blossom' "$VERIFY" "$fixture/ProviderBrands"
rm -rf "$fixture/ProviderBrands"; copy_fixture; printf changed >> "$fixture/ProviderBrands/provider-brand-cursor-2d.png"
expect_failure 'sha256 mismatch: provider-brand-cursor-2d' "$VERIFY" "$fixture/ProviderBrands"
rm -rf "$fixture/ProviderBrands"; copy_fixture; cp "$fixture/ProviderBrands/provider-brand-claude.png" "$fixture/ProviderBrands/undeclared.png"
expect_failure 'undeclared provider brand resource: undeclared.png' "$VERIFY" "$fixture/ProviderBrands"
echo 'provider brand asset integrity regression passed'
```

Run:

```bash
chmod 755 scripts/tests/provider-brand-assets-tests.sh
scripts/tests/provider-brand-assets-tests.sh
```

Expected: FAIL because the verifier does not exist.

- [ ] **Step 2: Copy exact official bytes and record literal provenance.**

Copy exactly one official source PNG per approved variant into the three fixed filenames. Renaming is permitted; changing pixels, vectors, transparency, proportions, colors, or padding is not. Record the literal outputs:

```bash
shasum -a 256 Sources/Needlbar/Resources/ProviderBrands/provider-brand-claude.png \
  Sources/Needlbar/Resources/ProviderBrands/provider-brand-openai-blossom.png \
  Sources/Needlbar/Resources/ProviderBrands/provider-brand-cursor-2d.png
file --brief --mime-type Sources/Needlbar/Resources/ProviderBrands/provider-brand-*.png
```

Create `ProviderBrandAssets.plist` with exactly the three resource IDs. Every entry contains `provider`, `file`, `sourcePage`, `sourceAsset`, `variant`, `imageType`, `rendering`, `fallbackSymbol`, and a literal 64-hex `sha256`.

```xml
<key>provider-brand-claude</key><dict>
 <key>provider</key><string>claude</string><key>file</key><string>provider-brand-claude.png</string>
 <key>sourcePage</key><string>https://brandfolder.com/anthropic/collection/newsroom</string>
 <key>variant</key><string>official orange Claude standalone mark</string>
 <key>imageType</key><string>image/png</string><key>rendering</key><string>officialOrange</string><key>fallbackSymbol</key><string>sparkles</string>
</dict>
<key>provider-brand-openai-blossom</key><dict>
 <key>provider</key><string>codex</string><key>file</key><string>provider-brand-openai-blossom.png</string>
 <key>sourcePage</key><string>https://openai.com/brand/</string>
 <key>variant</key><string>official monochrome Blossom standalone mark</string>
 <key>imageType</key><string>image/png</string><key>rendering</key><string>systemMonochrome</string><key>fallbackSymbol</key><string>chevron.left.forwardslash.chevron.right</string>
</dict>
<key>provider-brand-cursor-2d</key><dict>
 <key>provider</key><string>cursor</string><key>file</key><string>provider-brand-cursor-2d.png</string>
 <key>sourcePage</key><string>https://cursor.com/en-US/brand</string>
 <key>variant</key><string>official 2D standalone Cursor mark</string>
 <key>imageType</key><string>image/png</string><key>rendering</key><string>systemMonochrome</string><key>fallbackSymbol</key><string>cursorarrow</string>
</dict>
```

For each XML dictionary, insert one `sha256` key whose string value is the literal 64-hex value emitted for that same committed PNG above, and add the downloaded archive/file identifier as `sourceAsset` before commit. The verifier rejects a non-hex, zero, guessed, or mismatched value; never record signed URLs, cookies, credentials, account IDs, or raw archive content.

Create `TRADEMARKS.md`:

```markdown
# Provider brand assets

`provider-brand-claude`, `provider-brand-openai-blossom`, and
`provider-brand-cursor-2d` are official provider-distributed assets. Their
source pages, source asset identifiers, approved variants, image types, and
SHA-256 digests are recorded in `ProviderBrandAssets.plist`.

Claude and Anthropic marks are owned by Anthropic; OpenAI and Blossom marks are
owned by OpenAI; Cursor marks are owned by Cursor. Needlbar is not sponsored
by, endorsed by, or affiliated with Anthropic, OpenAI, or Cursor. Provider
asset licenses, trademark terms, and usage restrictions remain in force.
```

- [ ] **Step 3: Implement resources and the verifier.**

Change the package target:

```swift
.target(
    name: "NeedlbarApp",
    dependencies: ["NeedlbarCore", "CNeedlbar"],
    path: "Sources/Needlbar",
    resources: [.copy("Resources/ProviderBrands")]
),
```

Create `scripts/verify-provider-brand-assets.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
brands_dir="$1"
fail() { echo "provider-brand-assets: $*" >&2; exit 1; }
[[ -d "$brands_dir" ]] || fail 'expected one ProviderBrands directory argument'
manifest="$brands_dir/ProviderBrandAssets.plist"; notice="$brands_dir/TRADEMARKS.md"
[[ -f "$manifest" ]] || fail 'missing provider brand manifest'
[[ -f "$notice" ]] || fail 'missing provider brand trademark notice'
plutil -lint "$manifest" >/dev/null || fail 'invalid provider brand manifest'
grep -F 'Needlbar is not sponsored by, endorsed by, or affiliated with' "$notice" >/dev/null || fail 'missing provider brand non-affiliation notice'
verify() {
 local id="$1" provider="$2" rendering="$3" fallback="$4" file_name="$5" asset expected
 [[ "$(/usr/libexec/PlistBuddy -c "Print :$id:provider" "$manifest")" == "$provider" ]] || fail "invalid manifest mapping: $id"
 [[ "$(/usr/libexec/PlistBuddy -c "Print :$id:file" "$manifest")" == "$file_name" ]] || fail "invalid manifest mapping: $id"
 [[ "$(/usr/libexec/PlistBuddy -c "Print :$id:rendering" "$manifest")" == "$rendering" ]] || fail "invalid manifest mapping: $id"
 [[ "$(/usr/libexec/PlistBuddy -c "Print :$id:fallbackSymbol" "$manifest")" == "$fallback" ]] || fail "invalid manifest mapping: $id"
 [[ "$(/usr/libexec/PlistBuddy -c "Print :$id:imageType" "$manifest")" == image/png ]] || fail "incomplete provenance: $id"
 [[ "$(/usr/libexec/PlistBuddy -c "Print :$id:sourcePage" "$manifest")" == https://* ]] || fail "incomplete provenance: $id"
 [[ -n "$(/usr/libexec/PlistBuddy -c "Print :$id:sourceAsset" "$manifest")" && -n "$(/usr/libexec/PlistBuddy -c "Print :$id:variant" "$manifest")" ]] || fail "incomplete provenance: $id"
 expected="$(/usr/libexec/PlistBuddy -c "Print :$id:sha256" "$manifest")"
 [[ "$expected" =~ ^[[:xdigit:]]{64}$ ]] || fail "invalid sha256: $id"
 asset="$brands_dir/$file_name"
 [[ -f "$asset" ]] || fail "missing declared resource: $id"
 [[ -s "$asset" ]] || fail "empty declared resource: $id"
 [[ "$(file --brief --mime-type "$asset")" == image/png ]] || fail "wrong image type: $id"
 [[ "$(shasum -a 256 "$asset" | awk '{print $1}')" == "$expected" ]] || fail "sha256 mismatch: $id"
}
verify provider-brand-claude claude officialOrange sparkles provider-brand-claude.png
verify provider-brand-openai-blossom codex systemMonochrome chevron.left.forwardslash.chevron.right provider-brand-openai-blossom.png
verify provider-brand-cursor-2d cursor systemMonochrome cursorarrow provider-brand-cursor-2d.png
for file in "$brands_dir"/*; do
 [[ -f "$file" ]] || continue
 case "$(basename "$file")" in ProviderBrandAssets.plist|TRADEMARKS.md|provider-brand-claude.png|provider-brand-openai-blossom.png|provider-brand-cursor-2d.png) ;; *) fail "undeclared provider brand resource: $(basename "$file")" ;; esac
done
```

Add the test before package tests:

```make
test:
	cargo test --workspace --features bridge-test-runtime
	sh ./scripts/tests/vendor-tokscale-test.sh
	$(MAKE) swift-test
	./scripts/tests/provider-brand-assets-tests.sh
	$(MAKE) widget-extension-test
	$(MAKE) package-test
	$(MAKE) notarize-test
```

- [ ] **Step 4: Run GREEN and commit.**

```bash
chmod 755 scripts/verify-provider-brand-assets.sh
scripts/verify-provider-brand-assets.sh Sources/Needlbar/Resources/ProviderBrands
scripts/tests/provider-brand-assets-tests.sh
swift build --target NeedlbarApp
git diff --check
git add Package.swift Sources/Needlbar/Resources/ProviderBrands scripts/verify-provider-brand-assets.sh scripts/tests/provider-brand-assets-tests.sh Makefile
git commit -m "feat: bundle verified provider brand assets"
```

Expected: PASS and one asset/provenance/validator commit.

### Task 2: Build the shared ProviderBrandIcon component test-first

**Files:**

- Create: `Sources/Needlbar/ProviderBrandIcon.swift`
- Create: `Tests/NeedlbarTests/ProviderBrandIconTests.swift`

- [ ] **Step 1: Write failing component tests.**

Use `NSImage(size:)` local doubles and `ProviderBrandIcon.AssetLoader`, never network. Add:

```swift
@Test func providerBrandCatalogKeepsApprovedIdentityAndRendering() {
 let claude = ProviderBrandIcon.catalogueEntry(for: .claude)
 let codex = ProviderBrandIcon.catalogueEntry(for: .codex)
 let cursor = ProviderBrandIcon.catalogueEntry(for: .cursor)
 #expect(claude.resourceID == "provider-brand-claude")
 #expect(claude.rendering == .officialOrange)
 #expect(codex.resourceID == "provider-brand-openai-blossom")
 #expect(codex.visibleProviderName == "Codex")
 #expect(codex.rendering == .systemMonochrome)
 #expect(cursor.resourceID == "provider-brand-cursor-2d")
 #expect(cursor.rendering == .systemMonochrome)
 #expect([claude, codex, cursor].map(\.fallbackSymbol) == ["sparkles", "chevron.left.forwardslash.chevron.right", "cursorarrow"])
}
@Test func providerBrandPlansUseEighteenPointFitFrames() {
 let loader = ProviderBrandIcon.AssetLoader { _ in .success(NSImage(size: NSSize(width: 240, height: 120))) }
 for provider in ProviderID.allCases {
  let plan = ProviderBrandIcon.plan(for: provider, loader: loader)
  #expect(plan.frame == CGSize(width: 18, height: 18))
  #expect(plan.contentMode == .fit); #expect(plan.sourceAspectRatio == 2)
  #expect(plan.image != nil); #expect(plan.fallbackSymbol == nil)
 }
}
@Test func providerBrandFallbackKeepsIdentityAndFrame() {
 for failure in ProviderBrandIcon.AssetFailure.allCases {
  let plan = ProviderBrandIcon.plan(for: .codex, loader: .init { _ in .failure(failure) })
  #expect(plan.image == nil); #expect(plan.frame == CGSize(width: 18, height: 18))
  #expect(plan.fallbackSymbol == "chevron.left.forwardslash.chevron.right")
  #expect(plan.accessibilityLabel == "Codex"); #expect(plan.failure == failure)
 }
}
@Test func bundledProviderBrandResourcesResolve() {
 for provider in ProviderID.allCases { #expect(ProviderBrandIcon.plan(for: provider, loader: .bundle).image != nil) }
}
```

Add tests for decorative versus labelled accessibility and for zero/non-finite loaded image sizes becoming `.incompatible`. Add an `.aqua`/ `.darkAqua` test: Claude remains `.officialOrange`, Codex/Cursor remain `.systemMonochrome`.

Run:

```bash
source /Users/taejunoh/.cargo/env
make swift-test SWIFT_TEST_FILTER='providerBrandCatalogKeepsApprovedIdentityAndRendering\|providerBrandPlansUseEighteenPointFitFrames\|providerBrandFallbackKeepsIdentityAndFrame\|bundledProviderBrandResourcesResolve'
```

Expected: compile FAIL because `ProviderBrandIcon` does not exist.

- [ ] **Step 2: Implement one catalogue and local renderer.**

Create `ProviderBrandIcon.swift` with this complete API:

```swift
import AppKit
import NeedlbarCore
import OSLog
import SwiftUI

struct ProviderBrandIcon: View {
 enum Rendering: Equatable { case officialOrange, systemMonochrome }
 enum ContentMode: Equatable { case fit }
 enum Accessibility: Equatable { case decorative, labelled }
 enum AssetFailure: String, CaseIterable, Equatable { case missing, malformed, incompatible }
 struct CatalogueEntry: Equatable { let resourceID: String; let visibleProviderName: String; let rendering: Rendering; let fallbackSymbol: String }
 struct Plan { let image: NSImage?; let frame: CGSize; let contentMode: ContentMode; let sourceAspectRatio: CGFloat?; let rendering: Rendering; let fallbackSymbol: String?; let accessibilityLabel: String; let accessibility: Accessibility; let failure: AssetFailure? }
 struct AssetLoader {
  let load: (CatalogueEntry) -> Result<NSImage, AssetFailure>
  static let bundle = AssetLoader { entry in
   guard let url = Bundle.module.url(forResource: entry.resourceID, withExtension: "png", subdirectory: "ProviderBrands") else { return .failure(.missing) }
   guard let image = NSImage(contentsOf: url) else { return .failure(.malformed) }
   guard image.size.width.isFinite, image.size.height.isFinite, image.size.width > 0, image.size.height > 0 else { return .failure(.incompatible) }
   return .success(image)
  }
 }
 static let frame = CGSize(width: 18, height: 18)
 let provider: ProviderID; let accessibility: Accessibility; private let loader: AssetLoader
 init(provider: ProviderID, accessibility: Accessibility = .decorative, loader: AssetLoader = .bundle) { self.provider = provider; self.accessibility = accessibility; self.loader = loader }
 var body: some View {
  let plan = Self.plan(for: provider, accessibility: accessibility, loader: loader)
  Group {
   if let image = plan.image, plan.rendering == .systemMonochrome { Image(nsImage: image).resizable().scaledToFit().renderingMode(.template).foregroundStyle(.primary) }
   else if let image = plan.image { Image(nsImage: image).resizable().scaledToFit().renderingMode(.original) }
   else if let symbol = plan.fallbackSymbol { Image(systemName: symbol).resizable().scaledToFit().foregroundStyle(plan.rendering == .officialOrange ? Color.orange : Color.primary) }
  }.frame(width: Self.frame.width, height: Self.frame.height)
   .modifier(ProviderBrandAccessibility(label: plan.accessibilityLabel, mode: accessibility))
   .onAppear { ProviderBrandIconDiagnostics.record(provider: provider, resourceID: Self.catalogueEntry(for: provider).resourceID, failure: plan.failure) }
 }
 static func catalogueEntry(for provider: ProviderID) -> CatalogueEntry {
  switch provider {
  case .claude: .init(resourceID: "provider-brand-claude", visibleProviderName: "Claude", rendering: .officialOrange, fallbackSymbol: "sparkles")
  case .codex: .init(resourceID: "provider-brand-openai-blossom", visibleProviderName: "Codex", rendering: .systemMonochrome, fallbackSymbol: "chevron.left.forwardslash.chevron.right")
  case .cursor: .init(resourceID: "provider-brand-cursor-2d", visibleProviderName: "Cursor", rendering: .systemMonochrome, fallbackSymbol: "cursorarrow")
  }
 }
 static func plan(for provider: ProviderID, accessibility: Accessibility = .decorative, loader: AssetLoader = .bundle) -> Plan {
  let entry = catalogueEntry(for: provider)
  switch loader.load(entry) {
  case let .success(image): .init(image: image, frame: frame, contentMode: .fit, sourceAspectRatio: image.size.width / image.size.height, rendering: entry.rendering, fallbackSymbol: nil, accessibilityLabel: entry.visibleProviderName, accessibility: accessibility, failure: nil)
  case let .failure(failure): .init(image: nil, frame: frame, contentMode: .fit, sourceAspectRatio: nil, rendering: entry.rendering, fallbackSymbol: entry.fallbackSymbol, accessibilityLabel: entry.visibleProviderName, accessibility: accessibility, failure: failure)
  }
 }
}
private struct ProviderBrandAccessibility: ViewModifier {
 let label: String; let mode: ProviderBrandIcon.Accessibility
 func body(content: Content) -> some View { switch mode { case .decorative: content.accessibilityHidden(true); case .labelled: content.accessibilityLabel(label) } }
}
@MainActor private enum ProviderBrandIconDiagnostics {
 private static let logger = Logger(subsystem: "com.taejunoh.needlbar", category: "ProviderBrandIcon")
 private static var recorded = Set<String>()
 static func record(provider: ProviderID, resourceID: String, failure: ProviderBrandIcon.AssetFailure?) {
  guard let failure else { return }; let key = "\(provider.rawValue):\(resourceID):\(failure.rawValue)"
  guard recorded.insert(key).inserted else { return }
  logger.warning("provider brand fallback provider=\(provider.rawValue, privacy: .public) resource=\(resourceID, privacy: .public) failure=\(failure.rawValue, privacy: .public)")
 }
}
```

If access control prevents memberwise initializers, add explicit internal initializers matching the tests. Do not tint a loaded Claude image, log paths/bytes/accounts, or create another mapping.

- [ ] **Step 3: Run GREEN and commit.**

```bash
source /Users/taejunoh/.cargo/env
make swift-test SWIFT_TEST_FILTER='providerBrand\|bundledProviderBrandResourcesResolve'
git diff --check
git add Sources/Needlbar/ProviderBrandIcon.swift Tests/NeedlbarTests/ProviderBrandIconTests.swift
git commit -m "feat: add shared provider brand icon"
```

Expected: PASS and one component-only commit.

### Task 3: Apply ProviderBrandIcon to all five existing surfaces

**Files:**

- Modify: `Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift`
- Modify: `Sources/Needlbar/Modules/Overview/OverviewPopoverView.swift`
- Modify: `Sources/Needlbar/Modules/Provider/ProviderPopoverView.swift`
- Modify: `Sources/Needlbar/Settings/SystemMonitorSettingsView.swift`
- Modify: `Sources/Needlbar/Settings/SettingsView.swift`
- Create: `Tests/NeedlbarTests/ProviderBrandSurfaceContractTests.swift`

- [ ] **Step 1: Write failing surface and no-regression tests.**

Add this wiring test, a light/dark hosting test for the five local views, and retain existing dashboard metric/authentication/Fable/order/visibility/natural-height and browser/Cursor-action tests:

```swift
@Test func everyApprovedProviderSurfaceUsesTheSharedBrandIcon() throws {
 let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
 let paths = [
  "Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift",
  "Sources/Needlbar/Modules/Overview/OverviewPopoverView.swift",
  "Sources/Needlbar/Modules/Provider/ProviderPopoverView.swift",
  "Sources/Needlbar/Settings/SystemMonitorSettingsView.swift",
  "Sources/Needlbar/Settings/SettingsView.swift",
 ]
 for path in paths {
  let source = try String(contentsOf: root.appendingPathComponent(path))
  #expect(source.contains("ProviderBrandIcon(provider:"), "missing shared icon in \(path)")
  #expect(!source.contains("provider.systemImage"), "legacy provider symbol remains in \(path)")
 }
}
@Test @MainActor func brandIconAdoptionKeepsDashboardWidthAndVisibleHeightStable() {
 let model = SystemDashboardModel(snapshot: dashboardFixtureSnapshot(), configuration: SystemMonitorConfiguration())
 let measuring = NSHostingController(rootView: SystemDashboardPopoverView(measuring: model))
 let visible = NSHostingController(rootView: SystemDashboardPopoverView(model: model, height: 437))
 measuring.view.layoutSubtreeIfNeeded(); visible.view.layoutSubtreeIfNeeded()
 #expect(measuring.view.fittingSize.width == 312)
 #expect(visible.view.fittingSize == NSSize(width: 312, height: 437))
}
```

Run:

```bash
source /Users/taejunoh/.cargo/env
make swift-test SWIFT_TEST_FILTER='everyApprovedProviderSurfaceUsesTheSharedBrandIcon\|brandIconAdoptionKeepsDashboardWidthAndVisibleHeightStable\|dashboardPresentation\|dashboardFable\|dashboardBrowserLoginControl\|providerVisibilityAndMetricChangesAreIsolatedPerProvider\|authenticationRequiredQuotaSelectsTheProviderOwnedAction'
```

Expected: FAIL because direct provider SF Symbols remain.

- [ ] **Step 2: Make only the leading-icon replacements.**

Use these patterns; retain all existing text, values, help, callbacks, actions, disabled state, toggles, and pickers:

```swift
// SystemDashboardPopoverView.providerRow(_:)
ProviderBrandIcon(provider: provider.provider, accessibility: .decorative)
Text(provider.provider.displayName).fontWeight(.medium)

// Overview row
HStack(spacing: 6) { ProviderBrandIcon(provider: row.provider, accessibility: .decorative); Text(row.provider.displayName) }

// Provider detail headline
HStack(spacing: 6) { ProviderBrandIcon(provider: presentation.provider, accessibility: .decorative); Text(presentation.provider.displayName) }
.font(.headline)

// SystemMonitorSettingsView AI provider row
HStack(spacing: 6) { ProviderBrandIcon(provider: provider, accessibility: .decorative); Text(provider.displayName) }

// SettingsView.providerLoginRow(_:title:actionTitle:)
HStack(alignment: .top, spacing: 8) {
 ProviderBrandIcon(provider: provider, accessibility: .decorative)
 VStack(alignment: .leading, spacing: 2) {
  Text(title)
  Text(loginStatusCopy(for: provider)).font(.caption).foregroundStyle(.secondary)
 }
 Spacer()
 Button(actionTitle) { actions.connect(provider) }.disabled(isLoginInFlight(for: provider))
}
```

In the current Cursor Connections row, put `ProviderBrandIcon(provider: .cursor, accessibility: .decorative)` before its existing VStack and leave its button untouched. Retain `MonitorModuleID.systemImage`; remove only the old provider `systemImage` extension after no provider call site uses it.

- [ ] **Step 3: Run GREEN and commit.**

```bash
source /Users/taejunoh/.cargo/env
make swift-test SWIFT_TEST_FILTER='providerBrand\|dashboardPresentation\|dashboardNaturalHeight\|dashboardMeasurementAndVisibleHostsUse312PointWidth\|dashboardReadability\|dashboardFable\|dashboardBrowserLoginControl\|providerVisibilityAndMetricChangesAreIsolatedPerProvider\|providerReorderPersistsWithoutChangingProviderPreferences\|authenticationRequiredQuotaSelectsTheProviderOwnedAction\|cursorSpendingAction'
git diff --check
git add Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift Sources/Needlbar/Modules/Overview/OverviewPopoverView.swift Sources/Needlbar/Modules/Provider/ProviderPopoverView.swift Sources/Needlbar/Settings/SystemMonitorSettingsView.swift Sources/Needlbar/Settings/SettingsView.swift Tests/NeedlbarTests/ProviderBrandSurfaceContractTests.swift
git commit -m "feat: use provider brand icons across AI surfaces"
```

Expected: PASS and one UI-only commit; labels, values, actions, Fable, order/visibility, and 312-point adaptive behavior remain unchanged.

### Task 4: Validate the same resource bundle during package and smoke

**Files:**

- Modify: `scripts/package-app.sh`
- Modify: `scripts/smoke-app.sh`
- Modify: `scripts/tests/package-app-tests.sh`

- [ ] **Step 1: Write package RED checks.**

Extend the package fixture build to create `.build/arm64-apple-macosx/release/Needlbar_NeedlbarApp.bundle/ProviderBrands` with real manifest, notice, and PNGs. After a successful package run require:

```bash
installed_brands="$fixture_root/dist/Needlbar.app/Contents/Resources/Needlbar_NeedlbarApp.bundle/ProviderBrands"
[[ -d "$installed_brands" ]] || fail 'package did not install NeedlbarApp provider resources'
"$fixture_root/scripts/verify-provider-brand-assets.sh" "$installed_brands" || fail 'packaged provider resources failed integrity verification'
```

Before invoking the fixture package script, copy the real verifier and every source resource into its matching fixture paths and preserve its executable bit:

```bash
cp "$ROOT/scripts/verify-provider-brand-assets.sh" "$fixture_root/scripts/verify-provider-brand-assets.sh"
chmod 755 "$fixture_root/scripts/verify-provider-brand-assets.sh"
mkdir -p "$fixture_root/Sources/Needlbar/Resources/ProviderBrands"
cp "$ROOT/Sources/Needlbar/Resources/ProviderBrands/"provider-brand-*.png "$fixture_root/Sources/Needlbar/Resources/ProviderBrands/"
cp "$ROOT/Sources/Needlbar/Resources/ProviderBrands/ProviderBrandAssets.plist" "$fixture_root/Sources/Needlbar/Resources/ProviderBrands/"
cp "$ROOT/Sources/Needlbar/Resources/ProviderBrands/TRADEMARKS.md" "$fixture_root/Sources/Needlbar/Resources/ProviderBrands/"
```

Add isolated cases removing Cursor’s image and modifying OpenAI’s byte; expect `missing declared resource: provider-brand-cursor-2d` and `sha256 mismatch: provider-brand-openai-blossom`. Keep widget, public acceptance-driver, relink, entitlement, and signing-order checks.

Expected: `scripts/tests/package-app-tests.sh` FAILS because package does not yet validate or copy the resource bundle.

- [ ] **Step 2: Implement package and smoke checks.**

In `scripts/package-app.sh`, add:

```bash
BRAND_VERIFIER="$ROOT/scripts/verify-provider-brand-assets.sh"
SOURCE_BRANDS="$ROOT/Sources/Needlbar/Resources/ProviderBrands"
SWIFTPM_RESOURCE_BUNDLE="$ROOT/.build/arm64-apple-macosx/release/Needlbar_NeedlbarApp.bundle"
PACKAGED_BRANDS="$CONTENTS_PATH/Resources/Needlbar_NeedlbarApp.bundle/ProviderBrands"
```

After existing required-file checks:

```bash
[[ -x "$BRAND_VERIFIER" ]] || fail "missing provider brand verifier: $BRAND_VERIFIER"
"$BRAND_VERIFIER" "$SOURCE_BRANDS"
```

After release Swift build and before current host signing:

```bash
[[ -d "$SWIFTPM_RESOURCE_BUNDLE" ]] || fail "release provider resource bundle was not produced: $SWIFTPM_RESOURCE_BUNDLE"
cp -R "$SWIFTPM_RESOURCE_BUNDLE" "$CONTENTS_PATH/Resources/"
"$BRAND_VERIFIER" "$PACKAGED_BRANDS"
```

In `scripts/smoke-app.sh`:

```bash
BRAND_VERIFIER="$ROOT/scripts/verify-provider-brand-assets.sh"
BRAND_DIRECTORY="$APP_PATH/Contents/Resources/Needlbar_NeedlbarApp.bundle/ProviderBrands"
```

Inside `main()`, before Info.plist lint and launch:

```bash
[[ -x "$BRAND_VERIFIER" ]] || fail "missing provider brand verifier: $BRAND_VERIFIER"
"$BRAND_VERIFIER" "$BRAND_DIRECTORY"
```

Do not duplicate raw source assets, weaken codesigning, use `--deep`, or contact a network. Source verifier, `Bundle.module` unit test, package verifier, and smoke verifier together prove the three local lookup IDs, declared fallback symbols, and shipped resource bytes.

- [ ] **Step 3: Run GREEN and commit.**

```bash
source /Users/taejunoh/.cargo/env
make package-test
source /Users/taejunoh/.cargo/env
make package
source /Users/taejunoh/.cargo/env
make smoke
git diff --check
git add scripts/package-app.sh scripts/smoke-app.sh scripts/tests/package-app-tests.sh
git commit -m "build: verify bundled provider brand assets"
```

Expected: PASS and one packaging-only commit.

### Task 5: Full verification, bounded native evidence, and status handoff

**Files:**

- Modify after evidence: `docs/STATUS.md`
- Verify only: prior task files

- [ ] **Step 1: Run complete automated gates.**

```bash
source /Users/taejunoh/.cargo/env
make swift-test SWIFT_TEST_FILTER='providerBrand\|dashboard\|overview\|authentication\|providerVisibility\|providerReorder'
source /Users/taejunoh/.cargo/env
make test
source /Users/taejunoh/.cargo/env
make package
source /Users/taejunoh/.cargo/env
make smoke
git diff --check
git status --short
```

Expected: all exit 0. A focused test or browser mockup is insufficient.

- [ ] **Step 2: Inspect only the exact packaged worktree app.**

```bash
ps -axo pid,etime,args | rg '/Users/taejunoh/Developer/LFG/needlbar/.worktrees/.*/dist/Needlbar\.app/Contents/MacOS/Needlbar$'
```

Capture sanitized app-only light/dark evidence for: dashboard AI Usage (18-point orange Claude, monochrome Codex/Cursor, unchanged 312-point width/height/anchor/scroll/dismissal); Overview/provider detail; Settings provider display/Connections controls; and a development-only injected missing-loader fixture using the matching existing fallback. Do not rename/break a normal shipped asset, trigger provider actions, or retain account names, IPs, credentials, payloads, browser pages, or full-desktop images. Mark gaps unobserved. Native macOS 14 remains deferred.

- [ ] **Step 3: Record evidence and commit only documentation.**

Append `docs/STATUS.md` with commits, focused/full/package/smoke outputs and log paths, exact packaged executable hash, sanitized capture dimensions/paths, observed provider/appearance/surface/fallback/312-point/dismissal evidence, unobserved items, macOS 14 deferral, and confirmation that no runtime fetch, credential, account action, public app, widget, persisted setting, push, merge, notarization, or release changed.

```bash
shasum -a 256 dist/Needlbar.app/Contents/MacOS/Needlbar
git add docs/STATUS.md
git commit -m "docs: record provider brand icon verification"
```

Expected: documentation-only final commit. Do not push, merge, sign for distribution, notarize, publish, or release without a separate request.

## Plan self-review

**Spec coverage:** Tasks 1–2 cover provider-distributed-only assets, source/variant/SHA-256 manifest, trademark/non-affiliation, fixed resource IDs, 18-point aspect-fit frames, Claude-orange/system-monochrome treatment, fallback, accessibility, safe diagnostics, light/dark, and local failure cases. Task 3 covers every required application surface while preserving data/actions/adaptive sizing. Task 4 validates the exact compiled resource bundle offline in package and smoke. Task 5 requires complete automated and bounded native evidence with explicit macOS 14 deferral.

**Placeholder scan:** Every implementation type, file, command, fallback, source page, and test outcome is named. SHA-256 and source-asset identifiers must be literal outputs from the exact official byte acquisition; they cannot truthfully be invented in advance, and the verifier rejects invalid or mismatched values. The binary source bytes themselves must be copied unchanged, not reproduced in Markdown.

**Type consistency:** `ProviderID` is always the normalized input. `CatalogueEntry` solely owns resource ID/label/rendering/fallback; `AssetLoader` returns `Result<NSImage, AssetFailure>`; `Plan` carries frame/fallback/accessibility state; accessibility is decorative or labelled only. Package and smoke use the same `Needlbar_NeedlbarApp.bundle/ProviderBrands` location.
