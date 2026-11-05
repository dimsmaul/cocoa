import AppKit
import SwiftUI

final class QuickCapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}

/// Non-activating, so focus returns to the app you were using as soon as the panel closes.
@MainActor
final class QuickCaptureController: NSObject, NSWindowDelegate {
    private static let size = NSSize(width: 520, height: 60)

    private let taskStore: TaskStore
    private let timerManager: TimerManager
    private let panel: QuickCapturePanel

    init(taskStore: TaskStore, timerManager: TimerManager) {
        self.taskStore = taskStore
        self.timerManager = timerManager
        self.panel = QuickCapturePanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        super.init()

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.delegate = self
    }

    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    private func show() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(
                x: visible.midX - Self.size.width / 2,
                y: visible.maxY - visible.height * 0.28
            ))
        }

        // A new view each time, so the field always opens empty and focused.
        panel.contentView = NSHostingView(rootView: QuickCaptureView(
            onSubmit: { [weak self] title in
                self?.taskStore.captureTask(title: title)
                self?.timerManager.syncWithActiveTask()
                self?.hide()
            },
            onCancel: { [weak self] in
                self?.hide()
            }
        ))
        panel.makeKeyAndOrderFront(nil)
    }

    private func hide() {
        panel.orderOut(nil)
    }
}

private struct QuickCaptureView: View {
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var title = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.orange)
                .accessibilityHidden(true)

            TextField("Add a task to Inbox", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .focused($isFocused)
                .onSubmit { onSubmit(title) }
                .onExitCommand(perform: onCancel)
        }
        .padding(.horizontal, 18)
        .frame(width: 520, height: 60)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .preferredColorScheme(.dark)
        .onAppear {
            DispatchQueue.main.async {
                isFocused = true
            }
        }
    }
}
