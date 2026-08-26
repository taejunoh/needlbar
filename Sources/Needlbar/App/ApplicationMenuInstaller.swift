import AppKit

@MainActor
enum ApplicationMenuInstaller {
    static func install(in application: NSApplication) {
        let mainMenu = application.mainMenu ?? NSMenu(title: "Main Menu")
        let editItems = mainMenu.items.filter { $0.title == "Edit" }
        let editItem: NSMenuItem

        if let existingEditItem = editItems.first {
            editItem = existingEditItem
            for duplicate in editItems.dropFirst() {
                mainMenu.removeItem(duplicate)
            }
        } else {
            editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
            mainMenu.addItem(editItem)
        }

        let editMenu = editItem.submenu ?? NSMenu(title: "Edit")
        editItem.submenu = editMenu

        let pasteItems = editMenu.items.filter { $0.title == "Paste" }
        let pasteItem: NSMenuItem
        if let existingPasteItem = pasteItems.first {
            pasteItem = existingPasteItem
            for duplicate in pasteItems.dropFirst() {
                editMenu.removeItem(duplicate)
            }
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
