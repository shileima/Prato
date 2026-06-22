import AppKit

/// Builds the application main menu with keyboard shortcuts.
/// Called from AppDelegate to wire shortcuts into the responder chain.
@MainActor
enum MainMenuBuilder {

    static func buildMenu() -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(appMenu())
        mainMenu.addItem(fileMenu())
        mainMenu.addItem(editMenu())
        mainMenu.addItem(viewMenu())
        mainMenu.addItem(helpMenu())
        return mainMenu
    }

    // MARK: - App menu

    private static func appMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "Prato")
        menu.addItem(withTitle: "关于 Prato", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        let updatesItem = NSMenuItem(title: "检查更新…", action: #selector(Updater.checkForUpdates(_:)), keyEquivalent: "")
        updatesItem.target = Updater.shared
        menu.addItem(updatesItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Prato", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = menu
        return item
    }

    // MARK: - File menu

    private static func fileMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "文件")
        let newItem = menu.addItem(withTitle: "新建", action: #selector(AppDelegate.newProject(_:)), keyEquivalent: "n")
        newItem.target = NSApp.delegate
        let openItem = menu.addItem(withTitle: "打开…", action: #selector(AppDelegate.openProject(_:)), keyEquivalent: "o")
        openItem.target = NSApp.delegate
        menu.addItem(.separator())
        menu.addItem(withTitle: "保存", action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
        menu.addItem(withTitle: "另存为…", action: #selector(NSDocument.saveAs(_:)), keyEquivalent: "S")
        menu.addItem(.separator())

        let importItem = NSMenuItem(title: "导入媒体…", action: #selector(EditorActions.importMedia(_:)), keyEquivalent: "i")
        importItem.keyEquivalentModifierMask = [.command]
        menu.addItem(importItem)

        menu.addItem(.separator())

        let exportItem = NSMenuItem(title: "导出…", action: #selector(EditorActions.showExport(_:)), keyEquivalent: "e")
        exportItem.keyEquivalentModifierMask = [.command]
        menu.addItem(exportItem)

        item.submenu = menu
        return item
    }

    // MARK: - Edit menu

    private static func editMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "编辑")
        menu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        menu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        menu.addItem(.separator())
        menu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(.separator())

        let splitItem = NSMenuItem(title: "从播放头分割", action: #selector(EditorActions.splitAtPlayhead(_:)), keyEquivalent: "k")
        splitItem.keyEquivalentModifierMask = [.command]
        menu.addItem(splitItem)

        let trimStartItem = NSMenuItem(title: "修剪开头到播放头", action: #selector(EditorActions.trimStartToPlayhead(_:)), keyEquivalent: "q")
        trimStartItem.keyEquivalentModifierMask = []
        menu.addItem(trimStartItem)

        let trimEndItem = NSMenuItem(title: "修剪结尾到播放头", action: #selector(EditorActions.trimEndToPlayhead(_:)), keyEquivalent: "w")
        trimEndItem.keyEquivalentModifierMask = []
        menu.addItem(trimEndItem)

        menu.addItem(.separator())

        let deleteItem = NSMenuItem(title: "删除", action: #selector(EditorActions.deleteSelectedClips(_:)), keyEquivalent: "\u{8}") // backspace
        deleteItem.keyEquivalentModifierMask = []
        menu.addItem(deleteItem)

        item.submenu = menu
        return item
    }

    // MARK: - View menu

    private static func viewMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "视图")

        let mediaItem = NSMenuItem(title: "媒体面板", action: #selector(EditorActions.toggleMediaPanel(_:)), keyEquivalent: "0")
        mediaItem.keyEquivalentModifierMask = [.command]
        menu.addItem(mediaItem)

        let inspectorItem = NSMenuItem(title: "检查器", action: #selector(EditorActions.toggleInspectorPanel(_:)), keyEquivalent: "0")
        inspectorItem.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(inspectorItem)

        let agentItem = NSMenuItem(title: "智能体面板", action: #selector(EditorActions.toggleAgentPanel(_:)), keyEquivalent: "a")
        agentItem.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(agentItem)

        menu.addItem(.separator())

        let maximizeItem = NSMenuItem(title: "最大化当前面板", action: #selector(EditorActions.toggleMaximizePanel(_:)), keyEquivalent: "`")
        maximizeItem.keyEquivalentModifierMask = []
        menu.addItem(maximizeItem)

        menu.addItem(.separator())
        menu.addItem(layoutSubmenuItem())
        menu.addItem(.separator())
        menu.addItem(withTitle: "进入全屏", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        item.submenu = menu
        return item
    }

    private static func layoutSubmenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "布局", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "布局")

        let defaultItem = NSMenuItem(title: LayoutPreset.default.label, action: #selector(EditorActions.setLayoutDefault(_:)), keyEquivalent: "1")
        defaultItem.keyEquivalentModifierMask = [.command]
        submenu.addItem(defaultItem)

        let mediaItem = NSMenuItem(title: LayoutPreset.media.label, action: #selector(EditorActions.setLayoutMedia(_:)), keyEquivalent: "2")
        mediaItem.keyEquivalentModifierMask = [.command]
        submenu.addItem(mediaItem)

        let verticalItem = NSMenuItem(title: LayoutPreset.vertical.label, action: #selector(EditorActions.setLayoutVertical(_:)), keyEquivalent: "3")
        verticalItem.keyEquivalentModifierMask = [.command]
        submenu.addItem(verticalItem)

        item.submenu = submenu
        return item
    }

    // MARK: - Help menu

    private static func helpMenu() -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: "帮助")
        menu.addItem(withTitle: "教程", action: #selector(AppDelegate.showTutorial(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "键盘快捷键", action: #selector(AppDelegate.showKeyboardShortcuts(_:)), keyEquivalent: "?")
        menu.addItem(withTitle: "MCP 配置说明", action: #selector(AppDelegate.showMCPInstructions(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "发送反馈…", action: #selector(AppDelegate.showFeedback(_:)), keyEquivalent: "")
        item.submenu = menu
        return item
    }
}

/// Actions dispatched through the responder chain to reach the active EditorViewModel.
@MainActor @objc protocol EditorActions {
    func splitAtPlayhead(_ sender: Any?)
    func trimStartToPlayhead(_ sender: Any?)
    func trimEndToPlayhead(_ sender: Any?)
    func deleteSelectedClips(_ sender: Any?)
    func importMedia(_ sender: Any?)
    func playPause(_ sender: Any?)
    func stepFrameForward(_ sender: Any?)
    func stepFrameBackward(_ sender: Any?)
    func skipFramesForward(_ sender: Any?)
    func skipFramesBackward(_ sender: Any?)
    func showExport(_ sender: Any?)
    func toggleMediaPanel(_ sender: Any?)
    func toggleInspectorPanel(_ sender: Any?)
    func toggleAgentPanel(_ sender: Any?)
    func toggleMaximizePanel(_ sender: Any?)
    func setLayoutDefault(_ sender: Any?)
    func setLayoutMedia(_ sender: Any?)
    func setLayoutVertical(_ sender: Any?)
}
