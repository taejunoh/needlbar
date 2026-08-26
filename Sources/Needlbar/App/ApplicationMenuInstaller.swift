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
