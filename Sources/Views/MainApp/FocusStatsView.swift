import Charts
import SwiftUI

public struct FocusStatsView: View {
    let taskStore: TaskStore
    let timerManager: TimerManager

    public init(taskStore: TaskStore, timerManager: TimerManager) {
        self.taskStore = taskStore
        self.timerManager = timerManager
    }

    /// Includes the session still running, so the numbers move while the timer does.
    private var sessions: [FocusSession] {
        guard let running = timerManager.sessionTracker.current else { return taskStore.focusSessions }
        return taskStore.focusSessions + [running]
    }

    public var body: some View {
        let now = Date()

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Focus Stats")
                    .font(.system(size: 20, weight: .bold))

                HStack(spacing: 12) {
                    StatTile(label: "Today", seconds: FocusStats.secondsToday(sessions: sessions, now: now))
                    StatTile(label: "This week", seconds: FocusStats.secondsThisWeek(sessions: sessions, now: now))
                }

                StatsCard(title: "Focus time, last 7 days") {
                    FocusBarChart(days: FocusStats.lastSevenDays(sessions: sessions, now: now))
                }

                StatsCard(title: "Estimate vs actual, completed in the last 7 days") {
                    EstimateTable(rows: FocusStats.estimateVsActual(tasks: taskStore.tasks, now: now))
                }
            }
            .padding(24)
        }
    }
}

private struct StatTile: View {
    let label: String
    let seconds: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(FocusStats.formatted(seconds: seconds))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct StatsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct FocusBarChart: View {
    let days: [DailyFocus]

    @State private var hoveredDay: Date?

    private func minutes(_ day: DailyFocus) -> Double {
        Double(day.seconds) / 60
    }

    /// Headroom so the hover label above the tallest bar is not clipped; 30 minutes keeps an empty week readable.
    private var yMaximum: Double {
        max(days.map(minutes).max() ?? 0, 30) * 1.15
    }

    var body: some View {
        Chart(days) { day in
            BarMark(
                x: .value("Day", day.day, unit: .day),
                y: .value("Minutes", minutes(day)),
                width: .ratio(0.5)
            )
            .cornerRadius(4)
            .foregroundStyle(Color.orange.opacity(hoveredDay == nil || hoveredDay == day.day ? 1 : 0.45))
            .annotation(position: .top, spacing: 4) {
                if hoveredDay == day.day {
                    Text(FocusStats.formatted(seconds: day.seconds))
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                }
            }
            .accessibilityLabel(day.day.formatted(.dateTime.weekday(.wide).month().day()))
            .accessibilityValue(FocusStats.formatted(seconds: day.seconds))
        }
        .chartYScale(domain: 0...yMaximum)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                    .foregroundStyle(Color.primary.opacity(0.08))
                AxisValueLabel {
                    if let minutes = value.as(Double.self) {
                        Text("\(Int(minutes))m")
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let plotFrame = proxy.plotFrame else { return }
                            let x = location.x - geometry[plotFrame].minX
                            if let date: Date = proxy.value(atX: x) {
                                hoveredDay = Calendar.current.startOfDay(for: date)
                            }
                        case .ended:
                            hoveredDay = nil
                        }
                    }
            }
        }
        .frame(height: 200)
    }
}

private struct EstimateTable: View {
    let rows: [EstimateComparison]

    private let columnWidth: CGFloat = 70

    var body: some View {
        if rows.isEmpty {
            Text("Complete a task to compare its estimate with the time it took.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 8) {
                HStack {
                    Text("Task").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Estimate").frame(width: columnWidth, alignment: .trailing)
                    Text("Actual").frame(width: columnWidth, alignment: .trailing)
                    Text("Difference").frame(width: columnWidth, alignment: .trailing)
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)

                ForEach(rows.prefix(15)) { row in
                    HStack {
                        Text(row.title)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(FocusStats.formatted(seconds: row.estimatedSeconds))
                            .frame(width: columnWidth, alignment: .trailing)
                        Text(FocusStats.formatted(seconds: row.actualSeconds))
                            .frame(width: columnWidth, alignment: .trailing)
                        Text(difference(row))
                            .foregroundStyle(.secondary)
                            .frame(width: columnWidth, alignment: .trailing)
                    }
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func difference(_ row: EstimateComparison) -> String {
        let delta = row.actualSeconds - row.estimatedSeconds
        if delta == 0 { return "On time" }
        return (delta > 0 ? "+" : "−") + FocusStats.formatted(seconds: abs(delta))
    }
}
