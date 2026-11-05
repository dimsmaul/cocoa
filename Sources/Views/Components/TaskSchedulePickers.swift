import SwiftUI

// MARK: - Repeat Picker
public struct TaskRecurrencePickerButton: View {
    public let task: TaskItem
    @Bindable public var taskStore: TaskStore

    @State private var isShowingPopover = false

    public init(task: TaskItem, taskStore: TaskStore) {
        self.task = task
        self.taskStore = taskStore
    }

    public var body: some View {
        SidebarAttributeRow(
            icon: "repeat",
            iconColor: task.recurrence == nil ? .secondary : .orange,
            text: task.recurrence?.label ?? "Does not repeat",
            action: { isShowingPopover.toggle() }
        )
        .popover(isPresented: $isShowingPopover, arrowEdge: .bottom) {
            RecurrencePopover(
                recurrence: task.recurrence,
                onChange: { taskStore.setRecurrence(for: task.id, recurrence: $0) }
            )
        }
    }
}

private struct RecurrencePopover: View {
    let recurrence: TaskRecurrence?
    let onChange: (TaskRecurrence?) -> Void

    private static let options: [(title: String, frequency: TaskRecurrence.Frequency)] = [
        ("Daily", .daily),
        ("Weekdays", .weekdays),
        ("Weekly", .weekly),
        ("Monthly", .monthly)
    ]

    private var intervalUnit: String {
        switch recurrence?.frequency {
        case .weekly: return "week(s)"
        case .monthly: return "month(s)"
        default: return "day(s)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            PopoverHeader(title: "REPEAT")

            ScheduleOptionRow(title: "Does not repeat", isSelected: recurrence == nil) {
                onChange(nil)
            }

            ForEach(Self.options, id: \.frequency) { option in
                ScheduleOptionRow(title: option.title, isSelected: recurrence?.frequency == option.frequency) {
                    onChange(TaskRecurrence(frequency: option.frequency))
                }
            }

            if let recurrence, recurrence.frequency != .weekdays {
                Divider().padding(.vertical, 4)

                Stepper(
                    "Every \(max(1, recurrence.interval)) \(intervalUnit)",
                    value: Binding(
                        get: { max(1, recurrence.interval) },
                        set: { onChange(TaskRecurrence(frequency: recurrence.frequency, interval: $0)) }
                    ),
                    in: 1...99
                )
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            }
        }
        .padding(6)
        .frame(width: 210)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
    }
}

// MARK: - Reminder Picker
public struct TaskReminderPickerButton: View {
    public let task: TaskItem
    @Bindable public var taskStore: TaskStore

    @State private var isShowingPopover = false

    public init(task: TaskItem, taskStore: TaskStore) {
        self.task = task
        self.taskStore = taskStore
    }

    private var title: String {
        task.reminderAt?.formatted(date: .abbreviated, time: .shortened) ?? "No reminder"
    }

    public var body: some View {
        SidebarAttributeRow(
            icon: "bell.fill",
            iconColor: task.reminderAt == nil ? .secondary : .orange,
            text: title,
            action: { isShowingPopover.toggle() }
        )
        .popover(isPresented: $isShowingPopover, arrowEdge: .bottom) {
            ReminderPopover(
                task: task,
                onSelect: { date in
                    taskStore.setReminder(for: task.id, date: date)
                }
            )
        }
    }
}

private struct ReminderPopover: View {
    let task: TaskItem
    let onSelect: (Date?) -> Void

    @State private var customDate: Date
    private let reminders = ReminderService.shared

    init(task: TaskItem, onSelect: @escaping (Date?) -> Void) {
        self.task = task
        self.onSelect = onSelect
        self._customDate = State(initialValue: task.reminderAt ?? Date().addingTimeInterval(3600))
    }

    private var presets: [(title: String, date: Date)] {
        let calendar = Calendar.current
        let now = Date()
        var result = [(title: "In 1 hour", date: now.addingTimeInterval(3600))]

        func atNine(_ day: Date?) -> Date? {
            day.flatMap { calendar.date(bySettingHour: 9, minute: 0, second: 0, of: $0) }
        }
        if let tomorrow = atNine(calendar.date(byAdding: .day, value: 1, to: now)) {
            result.append(("Tomorrow at 9:00 AM", tomorrow))
        }
        if let due = task.dueDate {
            if let dayBefore = atNine(calendar.date(byAdding: .day, value: -1, to: due)), dayBefore > now {
                result.append(("Day before due, 9:00 AM", dayBefore))
            }
            if let dueDay = atNine(due), dueDay > now {
                result.append(("On due date, 9:00 AM", dueDay))
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            PopoverHeader(title: "REMIND ME")

            ForEach(presets, id: \.title) { preset in
                ScheduleOptionRow(title: preset.title, isSelected: task.reminderAt == preset.date) {
                    onSelect(preset.date)
                }
            }

            Divider().padding(.vertical, 4)

            HStack(spacing: 8) {
                DatePicker(
                    "Custom reminder time",
                    selection: $customDate,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.compact)

                Button("Set") {
                    onSelect(customDate)
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            if task.reminderAt != nil {
                ScheduleOptionRow(title: "Remove reminder", isSelected: false) {
                    onSelect(nil)
                }
            }

            if let warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
            }
        }
        .padding(6)
        .frame(width: 240)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
    }

    private var warning: String? {
        if !reminders.isAvailable {
            return "Reminders only work when Cocoa runs from Cocoa.app, not swift run."
        }
        if reminders.isDenied {
            return "Notifications are off for Cocoa. Turn them on in System Settings > Notifications."
        }
        return nil
    }
}

// MARK: - Task Row Indicators
public struct TaskScheduleBadges: View {
    public let task: TaskItem

    public init(task: TaskItem) {
        self.task = task
    }

    public var body: some View {
        if let recurrence = task.recurrence {
            Image(systemName: "repeat")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .help(recurrence.label)
                .accessibilityLabel("Repeats: \(recurrence.label)")
        }
        if let reminder = task.reminderAt, reminder > Date(), !task.isCompleted {
            let text = reminder.formatted(date: .abbreviated, time: .shortened)
            Image(systemName: "bell.fill")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .help("Reminder: \(text)")
                .accessibilityLabel("Reminder: \(text)")
        }
    }
}

// MARK: - Shared Popover Pieces
private struct PopoverHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .padding(.bottom, 2)
    }
}

private struct ScheduleOptionRow: View {
    let title: String
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isHovered ? Color.white.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
