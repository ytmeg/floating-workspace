import AppKit

@MainActor
public enum EditMenuController {
    public static func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "编辑")
        menu.addItem(NSMenuItem(
            title: "复制",
            action: #selector(NSTextView.copy(_:)),
            keyEquivalent: "c"
        ))
        menu.addItem(NSMenuItem(
            title: "粘贴",
            action: #selector(NSTextView.paste(_:)),
            keyEquivalent: "v"
        ))
        menu.addItem(NSMenuItem(
            title: "剪切",
            action: #selector(NSTextView.cut(_:)),
            keyEquivalent: "x"
        ))
        menu.addItem(NSMenuItem(
            title: "全选",
            action: #selector(NSTextView.selectAll(_:)),
            keyEquivalent: "a"
        ))
        menu.addItem(NSMenuItem(
            title: "撤销",
            action: NSSelectorFromString("undo:"),
            keyEquivalent: "z"
        ))
        let redo = NSMenuItem(
            title: "重做",
            action: NSSelectorFromString("redo:"),
            keyEquivalent: "Z"
        )
        redo.keyEquivalentModifierMask = .shift
        menu.addItem(redo)
        return menu
    }

    public static func install(on application: NSApplication) {
        let mainMenu = NSMenu()
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        editItem.submenu = makeMenu()
        mainMenu.addItem(editItem)
        application.mainMenu = mainMenu
    }
}
