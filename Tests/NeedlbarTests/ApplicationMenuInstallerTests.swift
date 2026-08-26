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

@MainActor
@Test func installingMenuTwicePreservesExistingEditItemsWithoutDuplicates() throws {
    let application = NSApplication.shared
    let previousMenu = application.mainMenu
    defer { application.mainMenu = previousMenu }

    let mainMenu = NSMenu(title: "Main Menu")
    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    mainMenu.addItem(NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""))
    mainMenu.item(withTitle: "Edit")?.submenu = editMenu
    application.mainMenu = mainMenu

    ApplicationMenuInstaller.install(in: application)
    ApplicationMenuInstaller.install(in: application)

    #expect(application.mainMenu?.items.filter { $0.title == "Edit" }.count == 1)
    #expect(editMenu.items.filter { $0.title == "Copy" }.count == 1)
    #expect(editMenu.items.filter { $0.title == "Paste" }.count == 1)
}

@MainActor
@Test func installingMenuPreservesAdditionalPreexistingEditAndPasteItems() throws {
    let application = NSApplication.shared
    let previousMenu = application.mainMenu
    defer { application.mainMenu = previousMenu }

    let mainMenu = NSMenu(title: "Main Menu")
    let primaryEditMenu = NSMenu(title: "Edit")
    let primaryPaste = NSMenuItem(title: "Paste", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    primaryEditMenu.addItem(primaryPaste)
    let extraPaste = NSMenuItem(title: "Paste", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    primaryEditMenu.addItem(extraPaste)
    let primaryEditItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
    primaryEditItem.submenu = primaryEditMenu
    mainMenu.addItem(primaryEditItem)

    let extraEditMenu = NSMenu(title: "Other Edit")
    let extraEditItemContent = NSMenuItem(title: "Custom Edit", action: #selector(NSText.deleteBackward(_:)), keyEquivalent: "")
    extraEditMenu.addItem(extraEditItemContent)
    let extraEditItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
    extraEditItem.submenu = extraEditMenu
    mainMenu.addItem(extraEditItem)
    application.mainMenu = mainMenu

    ApplicationMenuInstaller.install(in: application)

    #expect(mainMenu.items.contains { $0 === primaryEditItem })
    #expect(mainMenu.items.contains { $0 === extraEditItem })
    #expect(primaryEditMenu.items.contains { $0 === primaryPaste })
    #expect(primaryEditMenu.items.contains { $0 === extraPaste })
    #expect(primaryPaste.action == #selector(NSText.paste(_:)))
    #expect(primaryPaste.target == nil)
    #expect(primaryPaste.keyEquivalent == "v")
    #expect(primaryPaste.keyEquivalentModifierMask == [.command])
    #expect(extraPaste.action == #selector(NSText.cut(_:)))
    #expect(extraPaste.keyEquivalent == "x")
    #expect(extraEditMenu.items.contains { $0 === extraEditItemContent })
}
