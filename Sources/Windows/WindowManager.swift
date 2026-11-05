import AppKit
import SwiftUI

public enum CocoaUIMode {
    case mainApp
    case notchPill
    case floatingTower
}

@MainActor
public final class WindowManager: NSObject, NSWindowDelegate {
    public static let shared = WindowManager()

    public let taskStore = TaskStore()
    public lazy var timerManager = TimerManager(taskStore: taskStore)

    private var mainWindow: NSWindow?
    private var notchPanel: NotchPanel?
    private var floatingWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var mousePollTimer: Timer?
    private var lastMainWindowFrame: NSRect?
    private var lastTowerFrame: NSRect?
    private var isTransitioning = false
    private var quickCapture: QuickCaptureController?
    private var dayChangeObserver: NSObjectProtocol?

    public var currentMode: CocoaUIMode = .mainApp

    public override init() {
        super.init()
    }

    public func setup() {
        timerManager.setTaskStore(taskStore)

        setupStatusItem()
        setupMainWindow()
        setupNotchPanel()
        setupFloatingWindow()
        setupQuickCapture()
        setupReminders()
        setupDayRollover()

        // PRIMARY FOCUS: Open the Main App Window by default!
        showMode(.mainApp)
    }

    // MARK: - Quick Capture, Reminders & Day Rollover
    private func setupQuickCapture() {
        let controller = QuickCaptureController(taskStore: taskStore, timerManager: timerManager)
        quickCapture = controller
        GlobalHotkeyService.shared.onPressed = { [weak controller] in
            controller?.toggle()
        }
        applyQuickCaptureShortcut()
    }

    /// Returns false when macOS refuses the shortcut, usually because another app holds it.
    @discardableResult
    public func applyQuickCaptureShortcut() -> Bool {
        let settings = AppSettings.shared
        guard settings.isQuickCaptureEnabled else {
            GlobalHotkeyService.shared.unregister()
            return true
        }
        return GlobalHotkeyService.shared.register(settings.quickCaptureShortcut)
    }

    private func setupReminders() {
        let reminders = ReminderService.shared
        reminders.onOpenTask = { [weak self] id in
            guard let self, let task = self.taskStore.tasks.first(where: { $0.id == id }) else { return }
            // Selecting only: making it the active task would move a running timer onto it.
            self.taskStore.selectedTaskId = id
            self.taskStore.selectedSection = .board(task.board == .backlog ? .backlog : .inbox)
            self.showMode(.mainApp)
        }
        taskStore.onTasksSaved = { tasks in
            Task { @MainActor in
                ReminderService.shared.sync(tasks: tasks)
            }
        }
        reminders.start(tasks: taskStore.tasks)
    }

    private func setupDayRollover() {
        dayChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.taskStore.rollOverDueTasks()
            }
        }
    }

    // MARK: - Menu Bar Status Item
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            if let symbol = NSImage(systemSymbolName: "target", accessibilityDescription: "Cocoa")?.withSymbolConfiguration(config) {
                symbol.isTemplate = true
                button.image = symbol
                button.title = ""
            } else {
                button.title = "Cocoa"
            }
            button.action = #selector(statusItemClicked)
            button.target = self
        }
    }

    @objc private func statusItemClicked() {
        if mainWindow?.isVisible == true {
            showMode(.notchPill)
        } else {
            showMode(.mainApp)
        }
    }

    // MARK: - Main Application Window Setup
    private func setupMainWindow() {
        let initialWidth: CGFloat = 1020
        let initialHeight: CGFloat = 650

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 100, y: 100, width: 1200, height: 800)
        let x = screenFrame.midX - (initialWidth / 2.0)
        let y = screenFrame.midY - (initialHeight / 2.0)

        let window = NSWindow(
            contentRect: NSRect(x: x, y: y, width: initialWidth, height: initialHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "Cocoa"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 850, height: 500)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior = [.fullScreenPrimary, .canJoinAllSpaces]

        let mainView = MainAppView(
            taskStore: taskStore,
            timerManager: timerManager,
            onLaunchNotchMode: { [weak self] in
                self?.showMode(.notchPill)
            },
            onLaunchTowerMode: { [weak self] in
                self?.showMode(.floatingTower)
            }
        )

        window.contentView = NSHostingView(rootView: mainView)
        if let savedFrame = loadSavedMainWindowFrame() {
            window.setFrame(savedFrame, display: false)
            self.lastMainWindowFrame = savedFrame
        } else {
            self.lastMainWindowFrame = window.frame
        }
        self.mainWindow = window
    }

    // MARK: - Notch Panel Setup (Coucou Architecture)
    private func setupNotchPanel() {
        let notchGeo = NotchDetector.currentNotchGeometry()

        let panelW: CGFloat = 800
        let panelH: CGFloat = 560
        let x = notchGeo.topCenterPoint.x - (panelW / 2.0)
        let y = notchGeo.screenFrame.maxY - panelH

        let panel = NotchPanel(
            contentRect: NSRect(x: x, y: y, width: panelW, height: panelH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.currentIslandWidth = notchGeo.compactIslandWidth
        panel.currentIslandHeight = notchGeo.compactIslandHeight

        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)

        let pillView = NotchPillView(
            taskStore: taskStore,
            timerManager: timerManager,
            onDetachToFloating: { [weak self] in
                self?.showMode(.floatingTower)
            },
            onOpenMainApp: { [weak self] in
                self?.showMode(.mainApp)
            },
            onIslandBoundsChanged: { [weak panel] width, height in
                panel?.currentIslandWidth = width
                panel?.currentIslandHeight = height
            }
        )

        panel.contentView = NSHostingView(rootView: pillView)
        self.notchPanel = panel

        startMousePolling()
    }

    private func startMousePolling() {
        mousePollTimer?.invalidate()
        mousePollTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.notchPanel, panel.isVisible else { return }

                let mouse = NSEvent.mouseLocation
                let pf = panel.frame
                let localMouse = CGPoint(x: mouse.x - pf.minX, y: mouse.y - pf.minY)
                let islandRect = panel.currentIslandRect()
                let inIsland = islandRect.insetBy(dx: -6, dy: -6).contains(localMouse)

                if panel.ignoresMouseEvents == inIsland {
                    panel.ignoresMouseEvents = !inIsland
                }
            }
        }
    }

    // MARK: - Floating Tower Window Setup
    private func setupFloatingWindow() {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 100, y: 100, width: 1200, height: 800)
        let windowWidth: CGFloat = 330
        let windowHeight = FloatingTowerView.height

        let x = screenFrame.maxX - windowWidth - 40
        let y = screenFrame.maxY - windowHeight - 40

        let window = FloatingTowerWindow(
            contentRect: NSRect(x: x, y: y, width: windowWidth, height: windowHeight),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.appearance = NSAppearance(named: .darkAqua)

        let towerView = FloatingTowerView(
            taskStore: taskStore,
            timerManager: timerManager,
            onDockToNotch: { [weak self] in
                self?.showMode(.notchPill)
            },
            onOpenMainApp: { [weak self] in
                self?.showMode(.mainApp)
            }
        )

        window.contentView = NSHostingView(rootView: towerView)
        self.floatingWindow = window
    }

    // MARK: - Mode Switching with Smooth Dynamic Morph Animations
    public func showMode(_ mode: CocoaUIMode) {
        let previousMode = self.currentMode
        if previousMode == mode && mode == .mainApp && mainWindow?.isVisible == true {
            mainWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        self.currentMode = mode

        switch (previousMode, mode) {
        case (.mainApp, .notchPill):
            animateMainAppToNotch()

        case (.mainApp, .floatingTower):
            animateMainAppToTower()

        case (.notchPill, .mainApp):
            animateNotchToMainApp()

        case (.floatingTower, .mainApp):
            animateTowerToMainApp()

        case (.notchPill, .floatingTower):
            animateNotchToTower()

        case (.floatingTower, .notchPill):
            animateTowerToNotch()

        default:
            performImmediateTransition(to: mode)
        }
    }

    // MARK: - Animation 1: Main App -> Notch Pill (Sucks into Notch)
    private func animateMainAppToNotch() {
        guard let main = mainWindow, let panel = notchPanel else {
            performImmediateTransition(to: .notchPill)
            return
        }

        // Save current frame before animating
        lastMainWindowFrame = main.frame
        saveMainWindowFrame(main.frame)

        let notchGeo = NotchDetector.currentNotchGeometry()

        // Target compressed frame right at the notch
        let targetFrame = NSRect(
            x: notchGeo.topCenterPoint.x - (notchGeo.compactIslandWidth / 2.0),
            y: notchGeo.screenFrame.maxY - notchGeo.compactIslandHeight,
            width: notchGeo.compactIslandWidth,
            height: notchGeo.compactIslandHeight
        )

        // Setup Notch Panel ready to receive
        let panelW: CGFloat = 800
        let panelH: CGFloat = 560
        let px = notchGeo.topCenterPoint.x - (panelW / 2.0)
        let py = notchGeo.screenFrame.maxY - panelH
        panel.setFrame(NSRect(x: px, y: py, width: panelW, height: panelH), display: true)
        panel.alphaValue = 0.0
        panel.orderFront(nil)

        floatingWindow?.orderOut(nil)

        isTransitioning = true
        main.minSize = .zero
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.30
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1.0)
            context.allowsImplicitAnimation = true

            // Main window shrinks upward directly into the notch
            main.animator().alphaValue = 0.0
            main.animator().setFrame(targetFrame, display: true)

            // Notch island fades in simultaneously
            panel.animator().alphaValue = 1.0
        } completionHandler: { [weak self] in
            self?.isTransitioning = false
            main.orderOut(nil)
            main.alphaValue = 1.0
            main.minSize = NSSize(width: 850, height: 500)
            if let lastFrame = self?.lastMainWindowFrame {
                main.setFrame(lastFrame, display: false)
            }
        }
    }

    // MARK: - Animation 2: Main App -> Floating Tower (Morphs to desktop card)
    private func animateMainAppToTower() {
        guard let main = mainWindow, let tower = floatingWindow else {
            performImmediateTransition(to: .floatingTower)
            return
        }

        // Save current frame before animating
        lastMainWindowFrame = main.frame
        saveMainWindowFrame(main.frame)

        let towerTargetFrame = lastTowerFrame ?? tower.frame

        tower.setFrame(towerTargetFrame, display: true)
        tower.alphaValue = 0.0
        tower.makeKeyAndOrderFront(nil)

        notchPanel?.orderOut(nil)

        isTransitioning = true
        main.minSize = .zero
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1.0)
            context.allowsImplicitAnimation = true

            main.animator().alphaValue = 0.0
            main.animator().setFrame(towerTargetFrame, display: true)

            tower.animator().alphaValue = 1.0
        } completionHandler: { [weak self] in
            self?.isTransitioning = false
            main.orderOut(nil)
            main.alphaValue = 1.0
            main.minSize = NSSize(width: 850, height: 500)
            if let lastFrame = self?.lastMainWindowFrame {
                main.setFrame(lastFrame, display: false)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Animation 3: Notch Pill -> Main App (Blooms downward to user's saved window size & position)
    private func animateNotchToMainApp() {
        guard let main = mainWindow else {
            performImmediateTransition(to: .mainApp)
            return
        }

        let notchGeo = NotchDetector.currentNotchGeometry()
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 100, y: 100, width: 1200, height: 800)

        // Restore user's saved window position and size
        let targetFrame = lastMainWindowFrame ?? loadSavedMainWindowFrame() ?? NSRect(
            x: screen.midX - 510,
            y: screen.midY - 325,
            width: 1020,
            height: 650
        )
        self.lastMainWindowFrame = targetFrame

        // Start from compressed origin at the notch
        let startFrame = NSRect(
            x: notchGeo.topCenterPoint.x - (notchGeo.compactIslandWidth / 2.0),
            y: notchGeo.screenFrame.maxY - notchGeo.compactIslandHeight,
            width: notchGeo.compactIslandWidth,
            height: notchGeo.compactIslandHeight
        )

        isTransitioning = true
        main.minSize = .zero
        main.setFrame(startFrame, display: false)
        main.alphaValue = 0.0
        main.makeKeyAndOrderFront(nil)

        floatingWindow?.orderOut(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.32
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0) // spring curve
            context.allowsImplicitAnimation = true

            notchPanel?.animator().alphaValue = 0.0

            main.animator().alphaValue = 1.0
            main.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak self] in
            self?.isTransitioning = false
            main.minSize = NSSize(width: 850, height: 500)
            self?.notchPanel?.orderOut(nil)
            self?.notchPanel?.alphaValue = 1.0
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Animation 4: Floating Tower -> Main App (Expands to user's saved window size & position)
    private func animateTowerToMainApp() {
        guard let main = mainWindow, let tower = floatingWindow else {
            performImmediateTransition(to: .mainApp)
            return
        }

        lastTowerFrame = tower.frame
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 100, y: 100, width: 1200, height: 800)

        // Restore user's saved window position and size
        let targetFrame = lastMainWindowFrame ?? loadSavedMainWindowFrame() ?? NSRect(
            x: screen.midX - 510,
            y: screen.midY - 325,
            width: 1020,
            height: 650
        )
        self.lastMainWindowFrame = targetFrame

        isTransitioning = true
        main.minSize = .zero
        main.setFrame(tower.frame, display: false)
        main.alphaValue = 0.0
        main.makeKeyAndOrderFront(nil)

        notchPanel?.orderOut(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.30
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            context.allowsImplicitAnimation = true

            tower.animator().alphaValue = 0.0
            main.animator().alphaValue = 1.0
            main.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak self] in
            self?.isTransitioning = false
            main.minSize = NSSize(width: 850, height: 500)
            tower.orderOut(nil)
            tower.alphaValue = 1.0
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Animation 5: Notch Pill -> Floating Tower (Detaches from Notch)
    private func animateNotchToTower() {
        guard let tower = floatingWindow, let panel = notchPanel else {
            performImmediateTransition(to: .floatingTower)
            return
        }

        let notchGeo = NotchDetector.currentNotchGeometry()
        let targetFrame = lastTowerFrame ?? tower.frame

        let startFrame = NSRect(
            x: notchGeo.topCenterPoint.x - (targetFrame.width / 2.0),
            y: notchGeo.screenFrame.maxY - targetFrame.height,
            width: targetFrame.width,
            height: targetFrame.height
        )

        tower.setFrame(startFrame, display: false)
        tower.alphaValue = 0.0
        tower.makeKeyAndOrderFront(nil)

        mainWindow?.orderOut(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.32
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            context.allowsImplicitAnimation = true

            panel.animator().alphaValue = 0.0
            tower.animator().alphaValue = 1.0
            tower.animator().setFrame(targetFrame, display: true)
        } completionHandler: {
            panel.orderOut(nil)
            panel.alphaValue = 1.0
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Animation 6: Floating Tower -> Notch Pill (Docks into Notch)
    private func animateTowerToNotch() {
        guard let tower = floatingWindow, let panel = notchPanel else {
            performImmediateTransition(to: .notchPill)
            return
        }

        lastTowerFrame = tower.frame
        let notchGeo = NotchDetector.currentNotchGeometry()

        let panelW: CGFloat = 800
        let panelH: CGFloat = 560
        let px = notchGeo.topCenterPoint.x - (panelW / 2.0)
        let py = notchGeo.screenFrame.maxY - panelH
        panel.setFrame(NSRect(x: px, y: py, width: panelW, height: panelH), display: true)
        panel.alphaValue = 0.0
        panel.orderFront(nil)

        mainWindow?.orderOut(nil)

        let targetGlide = NSRect(
            x: notchGeo.topCenterPoint.x - (tower.frame.width / 2.0),
            y: notchGeo.screenFrame.maxY - tower.frame.height,
            width: tower.frame.width,
            height: tower.frame.height
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.30
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1.0)
            context.allowsImplicitAnimation = true

            tower.animator().setFrame(targetGlide, display: true)
            tower.animator().alphaValue = 0.0
            panel.animator().alphaValue = 1.0
        } completionHandler: { [weak self] in
            tower.orderOut(nil)
            tower.alphaValue = 1.0
            if let last = self?.lastTowerFrame {
                tower.setFrame(last, display: false)
            }
        }
    }

    // MARK: - Fallback Immediate Transition
    private func performImmediateTransition(to mode: CocoaUIMode) {
        switch mode {
        case .mainApp:
            notchPanel?.orderOut(nil)
            floatingWindow?.orderOut(nil)
            if let saved = lastMainWindowFrame ?? loadSavedMainWindowFrame() {
                mainWindow?.setFrame(saved, display: true)
            }
            mainWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)

        case .notchPill:
            mainWindow?.orderOut(nil)
            floatingWindow?.orderOut(nil)
            if let panel = notchPanel {
                let notchGeo = NotchDetector.currentNotchGeometry()
                let panelW: CGFloat = 800
                let panelH: CGFloat = 560
                let x = notchGeo.topCenterPoint.x - (panelW / 2.0)
                let y = notchGeo.screenFrame.maxY - panelH
                panel.setFrame(NSRect(x: x, y: y, width: panelW, height: panelH), display: true)
                panel.alphaValue = 1.0
                panel.orderFront(nil)
            }

        case .floatingTower:
            mainWindow?.orderOut(nil)
            notchPanel?.orderOut(nil)
            floatingWindow?.alphaValue = 1.0
            floatingWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // Window delegate to remember user's resized / moved window positions
    public func windowDidResize(_ notification: Notification) {
        guard !isTransitioning else { return }
        if let window = notification.object as? NSWindow {
            if window == mainWindow {
                lastMainWindowFrame = window.frame
                saveMainWindowFrame(window.frame)
            } else if window == floatingWindow {
                lastTowerFrame = window.frame
            }
        }
    }

    public func windowDidMove(_ notification: Notification) {
        guard !isTransitioning else { return }
        if let window = notification.object as? NSWindow {
            if window == mainWindow {
                lastMainWindowFrame = window.frame
                saveMainWindowFrame(window.frame)
            } else if window == floatingWindow {
                lastTowerFrame = window.frame
            }
        }
    }

    // MARK: - Window Frame Persistence
    private func saveMainWindowFrame(_ frame: NSRect) {
        let frameDict: [String: Double] = [
            "x": Double(frame.origin.x),
            "y": Double(frame.origin.y),
            "width": Double(frame.size.width),
            "height": Double(frame.size.height)
        ]
        UserDefaults.standard.set(frameDict, forKey: "CocoaSavedMainWindowFrame")
    }

    private func loadSavedMainWindowFrame() -> NSRect? {
        guard let dict = UserDefaults.standard.dictionary(forKey: "CocoaSavedMainWindowFrame") as? [String: Double],
              let x = dict["x"], let y = dict["y"],
              let width = dict["width"], let height = dict["height"],
              width >= 850, height >= 500 else {
            return nil
        }
        return NSRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
    }

    // MARK: - Settings Window
    public func showSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(taskStore: taskStore)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 740, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Cocoa Settings"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.center()
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = NSHostingView(rootView: settingsView)
        self.settingsWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Handle closing main window (keep running in menu bar / dock)
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender == mainWindow {
            sender.orderOut(nil)
            return false
        }
        return true
    }
}
