import SwiftUI

public struct ProgressRing: View {
    public let progress: Double
    public var lineWidth: CGFloat = 3.5
    public var ringColor: Color = .orange

    public init(progress: Double, lineWidth: CGFloat = 3.5, ringColor: Color = .orange) {
        self.progress = progress
        self.lineWidth = lineWidth
        self.ringColor = ringColor
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(ringColor.opacity(0.2), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: CGFloat(min(1.0, max(0.0, progress))))
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: progress)
        }
    }
}
