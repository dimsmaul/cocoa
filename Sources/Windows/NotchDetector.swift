import AppKit

public struct NotchGeometry: Sendable {
    public let hasPhysicalNotch: Bool
    public let notchWidth: CGFloat
    public let notchHeight: CGFloat
    public let earWidth: CGFloat
    public let screenFrame: NSRect
    public let topCenterPoint: CGPoint

    public var compactIslandWidth: CGFloat {
        if hasPhysicalNotch {
            return notchWidth + (earWidth * 2.0)
        } else {
            return 190.0
        }
    }

    public var compactIslandHeight: CGFloat {
        if hasPhysicalNotch {
            return max(32.0, notchHeight)
        } else {
            return 34.0
        }
    }

    public var expandedWidth: CGFloat {
        return 620.0
    }

    public var expandedHeight: CGFloat {
        return 350.0
    }
}

@MainActor
public enum NotchDetector {
    public static func currentNotchGeometry(for screen: NSScreen? = NSScreen.main) -> NotchGeometry {
        guard let screen = screen ?? NSScreen.main else {
            let defaultFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
            return NotchGeometry(
                hasPhysicalNotch: false,
                notchWidth: 185,
                notchHeight: 32,
                earWidth: 85,
                screenFrame: defaultFrame,
                topCenterPoint: CGPoint(x: 720, y: 900)
            )
        }

        let frame = screen.frame
        let safeTop = screen.safeAreaInsets.top
        let hasNotch = safeTop > 0

        var width: CGFloat = 185.0
        let height: CGFloat = hasNotch ? safeTop : 32.0
        var centerX: CGFloat = frame.midX

        if #available(macOS 12.0, *),
           let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea,
           leftArea.width > 0 && rightArea.width > 0 {
            let leftMaxX = leftArea.maxX
            let rightMinX = rightArea.minX
            if rightMinX > leftMaxX {
                width = rightMinX - leftMaxX
                centerX = (leftMaxX + rightMinX) / 2.0
            }
        }

        return NotchGeometry(
            hasPhysicalNotch: hasNotch,
            notchWidth: width,
            notchHeight: height,
            earWidth: 90.0,
            screenFrame: frame,
            topCenterPoint: CGPoint(x: centerX, y: frame.maxY)
        )
    }
}
