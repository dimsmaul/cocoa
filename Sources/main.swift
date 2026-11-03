import AppKit

// Check for headless Stdio MCP Server mode (e.g. from Claude Desktop, Cursor, Antigravity)
if CommandLine.arguments.contains("--mcp") {
    MCPServerService.runStdioServer()
    exit(0)
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupAppIcon()
        setupMainMenu()
        WindowManager.shared.setup()

        // Start background MCP Server if enabled in Settings
        if AppSettings.shared.isMCPServerEnabled {
            MCPServerService.shared.start()
        }
    }

    private func setupAppIcon() {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let iconImage = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = iconImage
        } else if let iconURL = Bundle.main.url(forResource: "CocoaLogo", withExtension: "png"),
                  let iconImage = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = iconImage
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            WindowManager.shared.showMode(.mainApp)
        }
        return true
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // Cocoa App Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Cocoa")
        appMenu.addItem(withTitle: "About Cocoa", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(NSMenuItem.separator())

        appMenu.addItem(withTitle: "Hide Cocoa", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h").keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Cocoa", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File Menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit Menu (Essential for Cut/Copy/Paste/Undo in TextFields)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // View Menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let mainAppItem = NSMenuItem(title: "Main Dashboard", action: #selector(openMainAction), keyEquivalent: "1")
        mainAppItem.target = self
        viewMenu.addItem(mainAppItem)

        let notchItem = NSMenuItem(title: "Focus in Notch Pill", action: #selector(openNotchAction), keyEquivalent: "2")
        notchItem.target = self
        viewMenu.addItem(notchItem)

        let towerItem = NSMenuItem(title: "Floating Tower", action: #selector(openTowerAction), keyEquivalent: "3")
        towerItem.target = self
        viewMenu.addItem(towerItem)

        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func openSettingsAction() {
        WindowManager.shared.showSettings()
    }

    @objc private func openMainAction() {
        WindowManager.shared.showMode(.mainApp)
    }

    @objc private func openNotchAction() {
        WindowManager.shared.showMode(.notchPill)
    }

    @objc private func openTowerAction() {
        WindowManager.shared.showMode(.floatingTower)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular) // Regular macOS App (visible in Dock & App Switcher)
app.run()
