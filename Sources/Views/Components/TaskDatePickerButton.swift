import SwiftUI

public struct TaskDatePickerButton: View {
    public let task: TaskItem
    @Bindable public var taskStore: TaskStore
    public var width: CGFloat = 130

    @State private var isShowingPopover: Bool = false
    @State private var displayedMonth: Date = Date()
    @State private var isHovered: Bool = false

    public init(task: TaskItem, taskStore: TaskStore, width: CGFloat = 130) {
        self.task = task
        self.taskStore = taskStore
        self.width = width
    }

    private var currentDueDate: Date {
        task.dueDate ?? Date()
    }

    private var dateTitle: String {
        let cal = Calendar.current
        if cal.isDateInToday(currentDueDate) {
            return "Today"
        } else if cal.isDateInTomorrow(currentDueDate) {
            return "Tomorrow"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy"
            return formatter.string(from: currentDueDate)
        }
    }

    public var body: some View {
        Button(action: {
            displayedMonth = currentDueDate
            isShowingPopover.toggle()
        }) {
            HStack(spacing: 0) {
                Text(dateTitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .padding(.leading, 8)

                Spacer()

                // Native macOS pop-up button blue badge with double chevrons
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.accentColor)
                        .frame(width: 17, height: 17)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.trailing, 2)
            }
            .frame(width: width, height: 21)
            .background(Color(nsColor: .controlColor))
            .clipShape(RoundedRectangle(cornerRadius: 5.5, style: .continuous))
            .opacity(isHovered ? 0.92 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .popover(isPresented: $isShowingPopover, arrowEdge: .bottom) {
            DatePickerCalendarPopover(
                selectedDate: currentDueDate,
                displayedMonth: $displayedMonth,
                onSelectDate: { date in
                    taskStore.setDueDate(for: task.id, date: date)
                    isShowingPopover = false
                }
            )
        }
    }
}

// MARK: - Minimal Dark Calendar Popover
private struct DatePickerCalendarPopover: View {
    let selectedDate: Date
    @Binding var displayedMonth: Date
    let onSelectDate: (Date) -> Void

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.fixed(32), spacing: 6), count: 7)

    private var monthYearTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: displayedMonth)
    }

    private var daysInDisplayedMonth: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth) else {
            return []
        }
        var dates: [Date?] = []
        let range = calendar.range(of: .day, in: .month, for: displayedMonth) ?? 1..<29
        let firstDayComponents = calendar.dateComponents([.year, .month], from: monthInterval.start)
        guard let firstDay = calendar.date(from: firstDayComponents) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: firstDay)

        for _ in 1..<firstWeekday {
            dates.append(nil)
        }

        for day in range {
            var comp = firstDayComponents
            comp.day = day
            if let date = calendar.date(from: comp) {
                dates.append(date)
            }
        }

        return dates
    }

    var body: some View {
        VStack(spacing: 12) {
            // Quick Presets: Today, Tomorrow, Next Week
            HStack(spacing: 8) {
                presetButton(title: "Today") {
                    onSelectDate(Date())
                }
                presetButton(title: "Tomorrow") {
                    let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                    onSelectDate(tomorrow)
                }
                presetButton(title: "Next Week") {
                    let nextWeek = calendar.date(byAdding: .day, value: 7, to: Date()) ?? Date()
                    onSelectDate(nextWeek)
                }
            }

            Divider()
                .background(Color.white.opacity(0.08))

            // Month Navigation
            HStack {
                Button(action: {
                    if let prev = calendar.date(byAdding: .month, value: -1, to: displayedMonth) {
                        displayedMonth = prev
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(5)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                Text(monthYearTitle)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

                Button(action: {
                    if let next = calendar.date(byAdding: .month, value: 1, to: displayedMonth) {
                        displayedMonth = next
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(5)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            // Weekday Headers
            HStack(spacing: 6) {
                ForEach(["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"], id: \.self) { d in
                    Text(d)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .frame(width: 32, alignment: .center)
                }
            }

            // Month Grid
            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(0..<daysInDisplayedMonth.count, id: \.self) { i in
                    if let date = daysInDisplayedMonth[i] {
                        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
                        let isToday = calendar.isDateInToday(date)
                        let dayNum = "\(calendar.component(.day, from: date))"

                        Button(action: { onSelectDate(date) }) {
                            ZStack {
                                if isSelected {
                                    Circle().fill(Color.orange)
                                } else if isToday {
                                    Circle().strokeBorder(Color.orange, lineWidth: 1.5)
                                }
                                Text(dayNum)
                                    .font(.system(size: 11, weight: (isSelected || isToday) ? .bold : .regular))
                                    .foregroundStyle(isSelected ? Color.black : (isToday ? Color.orange : Color.primary))
                            }
                            .frame(width: 32, height: 32)
                            .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(width: 32, height: 32)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 285)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
    }

    private func presetButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}
