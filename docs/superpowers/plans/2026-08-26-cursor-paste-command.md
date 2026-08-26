# Cursor Session Token Paste Command Implementation Plan

> **SUPERSEDED — 2026-08-26:** This plan is retained as historical implementation record
> only. The approved Cursor local-usage/dashboard amendment removes the Cursor token field
> and connection workflow, so this paste behavior is no longer active work. See
> [`2026-08-26-cursor-local-usage-dashboard-quota-design.md`](../specs/2026-08-26-cursor-local-usage-dashboard-quota-design.md).

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore native `⌘V` paste into Needlbar's Cursor session-token `SecureField` by installing a standard AppKit Edit menu while preserving all existing token handling.

**Architecture:** A small main-actor `ApplicationMenuInstaller` owns an idempotent `NSApp.mainMenu` Edit submenu. Needlbar's normal launch starts with no main menu, so repeated calls in that app-owned path do not add duplicate Edit/Paste items. If a host or test supplies multiple pre-existing same-title Edit or Paste items, ownership cannot be proven: the installer preserves all of them, selects the first Edit and first Paste in that Edit submenu, and repairs only that Paste item. Its Paste item uses `#selector(NSText.paste(_:))`, a `nil` target, key equivalent `v`, and the Command modifier so AppKit dispatches through the current first responder. `AppDelegate` invokes the installer at launch; Settings, Cursor session storage, and the Rust bridge remain untouched.

**Tech Stack:** Swift 6, AppKit, SwiftUI, Swift Testing, macOS 14+

**Spec:** `docs/superpowers/specs/2026-08-26-cursor-paste-command-design.md`

---

## File Map

- Create: `Sources/Needlbar/App/ApplicationMenuInstaller.swift` — idempotent AppKit Edit menu construction.
- Modify: `Sources/Needlbar/App/AppDelegate.swift` — install the menu during application launch.
- Create: `Tests/NeedlbarTests/ApplicationMenuInstallerTests.swift` — real generated-menu regression tests.
- Do not modify: `Sources/Needlbar/Settings/SettingsView.swift`, `Sources/Needlbar/Settings/SettingsWindowController.swift`, `Sources/Needlbar/Authentication/ProviderLoginCoordinator.swift`, Cursor bridge/session code, or Rust code.

## Task 1: Add the failing real-menu regression test

**Files:**

- Create: `Tests/NeedlbarTests/ApplicationMenuInstallerTests.swift`

- [ ] **Step 1: Write the failing menu-contract test**

Create a `@MainActor` Swift Testing test that resets `NSApplication.shared.mainMenu` for the duration of the test, invokes the not-yet-existing installer, finds the generated Edit submenu and Paste item, and checks the exact native command contract:

```swift
import AppKit
import Testing
@testable import NeedlbarApp

@MainActor
@Test func generatedEditMenuRoutesPasteThroughTheResponderChain() throws {
    let application = NSApplication.shared
    let previousMenu = application.mainMenu
    defer { application.mainMenu = previousMenu }
    application.mainMenu = nil

    ApplicationMenuInstaller.install(in: application)

    let editMenu = try #require(application.mainMenu?.item(withTitle: "Edit")?.submenu)
    let paste = try #require(editMenu.item(withTitle: "Paste"))
    #expect(paste.action == #selector(NSText.paste(_:)))
    #expect(paste.target == nil)
    #expect(paste.keyEquivalent == "v")
    #expect(paste.keyEquivalentModifierMask == [.command])
}
```

Add a second normal-path test that starts with no main menu, calls `ApplicationMenuInstaller.install(in:)` twice, and asserts that the main menu contains one Edit item and the Edit submenu contains one Paste item. Add a preservation/repair test that seeds the main menu with multiple same-title Edit items and multiple Paste items in the first Edit submenu, invokes the installer, asserts that all pre-existing Edit/Paste entries remain, and checks that only the first Edit/first Paste selection has the native action, nil target, `v` key equivalent, and Command modifier. Do not put a token, clipboard payload, or credential canary in any test.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
swift test --filter ApplicationMenuInstallerTests
```

Expected: FAIL at compilation because `ApplicationMenuInstaller` has not been defined. No test should access `NSPasteboard` or a real provider credential.

## Task 2: Implement the minimal AppKit menu installation

**Files:**

- Create: `Sources/Needlbar/App/ApplicationMenuInstaller.swift`
- Modify: `Sources/Needlbar/App/AppDelegate.swift`

- [ ] **Step 1: Add the idempotent installer**

Create `Sources/Needlbar/App/ApplicationMenuInstaller.swift` with the following complete implementation. It reuses an existing main menu, creates missing app-owned Edit/Paste entries, preserves all pre-existing same-title entries because their ownership cannot be proven, and repairs the first Paste item selected within the first Edit submenu to the exact native command contract:

```swift
import AppKit

@MainActor
enum ApplicationMenuInstaller {
    static func install(in application: NSApplication) {
        let mainMenu = application.mainMenu ?? NSMenu(title: "Main Menu")
        let editItem: NSMenuItem

        if let existingEditItem = mainMenu.items.first(where: { $0.title == "Edit" }) {
            editItem = existingEditItem
        } else {
            editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
            mainMenu.addItem(editItem)
        }

        let editMenu = editItem.submenu ?? NSMenu(title: "Edit")
        editItem.submenu = editMenu

        let pasteItem: NSMenuItem
        if let existingPasteItem = editMenu.items.first(where: { $0.title == "Paste" }) {
            pasteItem = existingPasteItem
        } else {
            pasteItem = NSMenuItem(
                title: "Paste",
                action: #selector(NSText.paste(_:)),
                keyEquivalent: "v"
            )
            editMenu.addItem(pasteItem)
        }

        pasteItem.action = #selector(NSText.paste(_:))
        pasteItem.target = nil
        pasteItem.keyEquivalent = "v"
        pasteItem.keyEquivalentModifierMask = [.command]
        application.mainMenu = mainMenu
    }
}
```

The Paste item must be created or repaired with this exact configuration:

```swift
let pasteItem = NSMenuItem(
    title: "Paste",
    action: #selector(NSText.paste(_:)),
    keyEquivalent: "v"
)
pasteItem.target = nil
pasteItem.keyEquivalentModifierMask = [.command]
```

Do not add a key monitor, pasteboard read, token transformation, logging, or custom responder. Preserve all existing menu content, including multiple same-title Edit or Paste entries supplied by a host/test; the regression fix only requires repairing the first Paste item selected within the first Edit submenu.

- [ ] **Step 2: Call the installer during app launch**

At the beginning of `AppDelegate.applicationDidFinishLaunching(_:)`, after the application is available and before starting lifecycle observation/refresh tasks, call:

```swift
ApplicationMenuInstaller.install(in: NSApp)
```

Do not alter the existing Cursor `SecureField`, `cursorSessionToken` binding, connection controller, or bridge calls.

- [ ] **Step 3: Run the focused tests and verify GREEN**

Run:

```bash
swift test --filter ApplicationMenuInstallerTests
```

Expected: all tests in `ApplicationMenuInstallerTests` PASS, including the action, nil target, `v` key equivalent, Command modifier, and idempotence assertions.

## Task 3: Run integration verification and manual UI smoke

**Files:**

- No additional production files.

- [ ] **Step 1: Check formatting and diff hygiene**

Run:

```bash
git diff --check
swift format lint --recursive Sources/Needlbar/App Tests/NeedlbarTests/ApplicationMenuInstallerTests.swift
```

Expected: both commands exit 0. If the repository's installed Swift toolchain does not provide `swift format`, run the repository's existing Swift formatting/lint command instead and record the exact command/output; do not make unrelated formatting changes.

- [ ] **Step 2: Run the project-wide verification gate**

Run:

```bash
make test
```

Expected: exit 0 with the existing Rust and Swift suites passing. No Cursor token, clipboard payload, or provider login is required for this gate.

- [ ] **Step 3: Perform the bounded manual paste smoke**

Use a harmless fixture such as `NEEDLBAR-PASTE-SMOKE`, never a real token. Copy it with normal macOS UI, launch Needlbar, open Settings, focus the Cursor session-token field, and press `⌘V`. Confirm the field displays masked input. Clear the field without clicking Connect, then clear the harmless clipboard fixture. Confirm the field remains transient and the existing Connect/Reconnect flow is unchanged. Do not print or capture clipboard contents.

- [ ] **Step 4: Report the handoff**

Report the focused test, `make test`, diff check, and manual smoke results. The integration owner updates `docs/STATUS.md` and commits the production/test changes; this plan task does not authorize a release, provider login, credential capture, or push by itself.

## Plan Self-Review Checklist

- [x] Paste uses exactly `NSText.paste(_:)`, target `nil`, key equivalent `v`, and Command modifier.
- [x] The menu is installed at application launch and is idempotent in the clean app-owned path; pre-existing duplicate Edit/Paste entries are preserved, with only the first selected Paste repaired.
- [x] Regression coverage inspects a real generated AppKit menu rather than a fake paste path.
- [x] Cursor SecureField/session storage/bridge behavior remains unchanged.
- [x] No clipboard or token contents are read, logged, persisted, or placed in tests.
- [x] The manual smoke uses only a harmless fixture and does not submit it.
- [x] Focused Swift verification and full `make test` are required.
