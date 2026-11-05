import Foundation

public struct PendingReminder: Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let fireDate: Date

    public init(id: UUID, title: String, fireDate: Date) {
        self.id = id
        self.title = title
        self.fireDate = fireDate
    }
}

public enum ReminderPlan {
    public static func pending(tasks: [TaskItem], now: Date) -> [UUID: PendingReminder] {
        var result: [UUID: PendingReminder] = [:]
        for task in tasks where !task.isCompleted {
            if let fireDate = task.reminderAt, fireDate > now {
                result[task.id] = PendingReminder(id: task.id, title: task.title, fireDate: fireDate)
            }
        }
        return result
    }

    public static func diff(
        from old: [UUID: PendingReminder],
        to new: [UUID: PendingReminder]
    ) -> (added: [PendingReminder], removedIds: [UUID]) {
        let removedIds = old.filter { new[$0.key] != $0.value }.map(\.key)
        let added = new.filter { old[$0.key] != $0.value }.map(\.value)
        return (added, removedIds)
    }
}
