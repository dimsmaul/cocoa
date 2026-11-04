import AppKit

public final class FloatingTowerWindow: NSWindow {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }

    public override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            if !isKeyWindow {
                makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        super.sendEvent(event)
    }
}
