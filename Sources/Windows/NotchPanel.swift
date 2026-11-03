import AppKit

public final class NotchPanel: NSPanel {
    public var currentIslandWidth: CGFloat = 365
    public var currentIslandHeight: CGFloat = 32

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    /// Coucou trick: Prevent macOS from forcibly pushing the window below the menu bar and notch!
    public override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }

    public func currentIslandRect() -> NSRect {
        let x = (frame.width - currentIslandWidth) / 2.0
        let y = frame.height - currentIslandHeight
        return NSRect(x: x, y: y, width: currentIslandWidth, height: currentIslandHeight)
    }
}
