import Foundation

public struct TaskRecurrence: Codable, Equatable, Sendable {
    public enum Frequency: String, Codable, CaseIterable, Sendable {
        case daily
        case weekdays
        case weekly
        case monthly
    }

    public var frequency: Frequency
    /// Every N days, weeks, or months. Ignored by `.weekdays`.
    public var interval: Int

    public init(frequency: Frequency, interval: Int = 1) {
        self.frequency = frequency
        self.interval = interval
    }

    public var label: String {
        let count = max(1, interval)
        switch frequency {
        case .weekdays: return "Every weekday"
        case .daily: return count == 1 ? "Every day" : "Every \(count) days"
        case .weekly: return count == 1 ? "Every week" : "Every \(count) weeks"
        case .monthly: return count == 1 ? "Every month" : "Every \(count) months"
        }
    }

    /// First scheduled date after today. Missed occurrences are skipped, and completing
    /// a task early keeps the original schedule.
    public func nextDueDate(from due: Date?, now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        var next = due ?? now
        repeat {
            next = advanced(from: next, calendar: calendar)
        } while calendar.startOfDay(for: next) <= today
        return next
    }

    private func advanced(from date: Date, calendar: Calendar) -> Date {
        let count = max(1, interval)
        let result: Date?
        switch frequency {
        case .daily:
            result = calendar.date(byAdding: .day, value: count, to: date)
        case .weekly:
            result = calendar.date(byAdding: .weekOfYear, value: count, to: date)
        case .monthly:
            // ponytail: the 31st clamps to the 28th and stays there; store an anchor day if that matters.
            result = calendar.date(byAdding: .month, value: count, to: date)
        case .weekdays:
            var candidate = calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
            while calendar.isDateInWeekend(candidate) {
                candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate.addingTimeInterval(86_400)
            }
            result = candidate
        }
        return result ?? date.addingTimeInterval(86_400)
    }
}

public enum RecurringTasks {
    /// Inserts the next occurrence after a completed task and moves the recurrence onto it,
    /// so completing the old task a second time cannot create a duplicate.
    @discardableResult
    public static func handOff(
        tasks: inout [TaskItem],
        completedId: UUID,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TaskItem? {
        guard let index = tasks.firstIndex(where: { $0.id == completedId }),
              let recurrence = tasks[index].recurrence else { return nil }

        let completed = tasks[index]
        let nextDue = recurrence.nextDueDate(from: completed.dueDate, now: now, calendar: calendar)
        let next = TaskItem(
            title: completed.title,
            notes: completed.notes,
            estimatedMinutes: completed.estimatedMinutes,
            priority: completed.priority,
            listName: completed.listName,
            subtasks: completed.subtasks.map(freshSubtask),
            board: .upcoming,
            dueDate: nextDue,
            recurrence: recurrence,
            reminderAt: shiftedReminder(of: completed, to: nextDue, now: now, calendar: calendar)
        )

        tasks[index].recurrence = nil
        tasks[index].spawnedOccurrenceId = next.id
        tasks.insert(next, at: index + 1)
        return next
    }

    /// Undoes a hand-off when a completed task is reopened. Returns the occurrence the caller
    /// should delete, or nil when there is none or work on it has already started.
    public static func reopen(tasks: inout [TaskItem], reopenedId: UUID) -> UUID? {
        guard let index = tasks.firstIndex(where: { $0.id == reopenedId }),
              let nextId = tasks[index].spawnedOccurrenceId else { return nil }

        tasks[index].spawnedOccurrenceId = nil
        guard let next = tasks.first(where: { $0.id == nextId }),
              !next.isCompleted,
              next.timeSpentSeconds == 0 else { return nil }

        tasks[index].recurrence = next.recurrence
        return nextId
    }

    /// Moves Upcoming tasks that have reached their due date onto Today.
    public static func rollOverDueTasks(_ tasks: inout [TaskItem], now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: now)
        var changed = false
        for index in tasks.indices where tasks[index].board == .upcoming {
            if let due = tasks[index].dueDate, calendar.startOfDay(for: due) <= today {
                tasks[index].board = .today
                changed = true
            }
        }
        return changed
    }

    private static func freshSubtask(_ subtask: SubtaskItem) -> SubtaskItem {
        SubtaskItem(title: subtask.title, subtasks: subtask.subtasks.map(freshSubtask))
    }

    private static func shiftedReminder(of task: TaskItem, to nextDue: Date, now: Date, calendar: Calendar) -> Date? {
        guard let reminder = task.reminderAt else { return nil }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: task.dueDate ?? now),
            to: calendar.startOfDay(for: nextDue)
        ).day ?? 0
        guard let shifted = calendar.date(byAdding: .day, value: days, to: reminder), shifted > now else { return nil }
        return shifted
    }
}
