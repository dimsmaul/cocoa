import Foundation
import SwiftUI

public enum ListColorChoice: String, CaseIterable, Identifiable, Codable, Sendable {
    case orange
    case blue
    case purple
    case green
    case pink
    case red
    case yellow
    case teal
    case indigo
    case mint

    public var id: String { rawValue }

    public var color: Color {
        switch self {
        case .orange: return Color(red: 1.0, green: 0.58, blue: 0.0)
        case .blue: return Color(red: 0.04, green: 0.52, blue: 1.0)
        case .purple: return Color(red: 0.75, green: 0.35, blue: 0.95)
        case .green: return Color(red: 0.19, green: 0.82, blue: 0.35)
        case .pink: return Color(red: 1.0, green: 0.22, blue: 0.37)
        case .red: return Color(red: 1.0, green: 0.27, blue: 0.23)
        case .yellow: return Color(red: 1.0, green: 0.84, blue: 0.04)
        case .teal: return Color(red: 0.39, green: 0.82, blue: 1.0)
        case .indigo: return Color(red: 0.37, green: 0.36, blue: 0.9)
        case .mint: return Color(red: 0.39, green: 0.9, blue: 0.89)
        }
    }
}

public enum TaskBoard: String, Codable, CaseIterable, Sendable {
    case inbox = "Inbox"
    case today = "Today"
    case upcoming = "Upcoming"
    case backlog = "Backlog"
    case done = "Completed"

    public var iconName: String {
        switch self {
        case .inbox: return "tray.fill"
        case .today: return "sun.max.fill"
        case .upcoming: return "calendar"
        case .backlog: return "archivebox.fill"
        case .done: return "checkmark.circle.fill"
        }
    }
}

public enum TaskPriority: String, Codable, CaseIterable, Sendable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    public var colorName: String {
        switch self {
        case .low: return "blue"
        case .medium: return "orange"
        case .high: return "red"
        }
    }
}

public struct SubtaskItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var isCompleted: Bool
    public var subtasks: [SubtaskItem]

    public init(id: UUID = UUID(), title: String, isCompleted: Bool = false, subtasks: [SubtaskItem] = []) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.subtasks = subtasks
    }

    enum CodingKeys: String, CodingKey {
        case id, title, isCompleted, subtasks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        self.subtasks = try container.decodeIfPresent([SubtaskItem].self, forKey: .subtasks) ?? []
    }
}

public struct TaskComment: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var author: String
    public var content: String
    public var createdAt: Date

    public init(id: UUID = UUID(), author: String = "You", content: String, createdAt: Date = Date()) {
        self.id = id
        self.author = author
        self.content = content
        self.createdAt = createdAt
    }

    public var formattedDate: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(createdAt) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return "Today at \(formatter.string(from: createdAt))"
        } else if calendar.isDateInYesterday(createdAt) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return "Yesterday at \(formatter.string(from: createdAt))"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, h:mm a"
            return formatter.string(from: createdAt)
        }
    }
}

public struct TaskItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var notes: String
    public var estimatedMinutes: Int
    public var timeSpentSeconds: Int
    public var isCompleted: Bool
    public var priority: TaskPriority
    public var listName: String
    public var subtasks: [SubtaskItem]
    public var comments: [TaskComment]
    public var completedAt: Date?
    public var createdAt: Date
    public var board: TaskBoard
    public var dueDate: Date?
    public var recurrence: TaskRecurrence?
    public var reminderAt: Date?
    /// Next occurrence created when this task was completed, kept so reopening can undo it.
    public var spawnedOccurrenceId: UUID?

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        estimatedMinutes: Int = 25,
        timeSpentSeconds: Int = 0,
        isCompleted: Bool = false,
        priority: TaskPriority = .medium,
        listName: String = "General",
        subtasks: [SubtaskItem] = [],
        comments: [TaskComment] = [],
        completedAt: Date? = nil,
        createdAt: Date = Date(),
        board: TaskBoard = .today,
        dueDate: Date? = nil,
        recurrence: TaskRecurrence? = nil,
        reminderAt: Date? = nil,
        spawnedOccurrenceId: UUID? = nil
    ) {
        self.recurrence = recurrence
        self.reminderAt = reminderAt
        self.spawnedOccurrenceId = spawnedOccurrenceId
        self.id = id
        self.title = title
        self.notes = notes
        self.estimatedMinutes = estimatedMinutes
        self.timeSpentSeconds = timeSpentSeconds
        self.isCompleted = isCompleted
        self.priority = priority
        self.listName = listName
        self.subtasks = subtasks
        self.comments = comments
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.board = board
        if let dueDate {
            self.dueDate = dueDate
        } else if board == .today {
            self.dueDate = Date()
        } else if board == .upcoming {
            self.dueDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())
        } else {
            self.dueDate = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, notes, estimatedMinutes, timeSpentSeconds, isCompleted, priority
        case listName, subtasks, comments, completedAt, createdAt, board, dueDate
        case recurrence, reminderAt, spawnedOccurrenceId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.notes = NotesFormat.normalized(try container.decodeIfPresent(String.self, forKey: .notes) ?? "")
        self.estimatedMinutes = try container.decodeIfPresent(Int.self, forKey: .estimatedMinutes) ?? 25
        self.timeSpentSeconds = try container.decodeIfPresent(Int.self, forKey: .timeSpentSeconds) ?? 0
        self.isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        self.priority = try container.decodeIfPresent(TaskPriority.self, forKey: .priority) ?? .medium
        self.listName = try container.decodeIfPresent(String.self, forKey: .listName) ?? "General"
        self.subtasks = try container.decodeIfPresent([SubtaskItem].self, forKey: .subtasks) ?? []
        self.comments = try container.decodeIfPresent([TaskComment].self, forKey: .comments) ?? []
        self.completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.board = try container.decodeIfPresent(TaskBoard.self, forKey: .board) ?? .today
        self.dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        // An unreadable rule must not fail the whole tasks file and lose every task on the next save.
        self.recurrence = (try? container.decodeIfPresent(TaskRecurrence.self, forKey: .recurrence)) ?? nil
        self.reminderAt = try container.decodeIfPresent(Date.self, forKey: .reminderAt)
        self.spawnedOccurrenceId = try container.decodeIfPresent(UUID.self, forKey: .spawnedOccurrenceId)
    }

    /// Inbox is the working view of overdue, today, and upcoming tasks. Backlog has its own menu.
    public var isInInbox: Bool {
        !isCompleted && board != .backlog
    }

    /// The Today group in Inbox and the Today tab in Tower. A task with no date counts as
    /// today unless it is Upcoming, so newly captured tasks are always visible.
    public func isInTodayGroup(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard isInInbox else { return false }
        if let dueDate {
            return calendar.isDate(dueDate, inSameDayAs: now)
        }
        return board == .today || board == .inbox
    }

    /// Quick capture always lands in the Inbox, whatever board the main window is showing.
    public static func quickCapture(title: String) -> TaskItem? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return TaskItem(title: trimmed, listName: "General", board: .inbox)
    }

    public var formattedDueDate: String? {
        guard let dueDate else { return nil }
        let calendar = Calendar.current
        if calendar.isDateInToday(dueDate) {
            return "Today"
        } else if calendar.isDateInTomorrow(dueDate) {
            return "Tomorrow"
        } else if calendar.isDateInYesterday(dueDate) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: dueDate)
        }
    }

    public var estimatedSeconds: Int {
        return max(1, estimatedMinutes * 60)
    }

    public var progress: Double {
        guard estimatedSeconds > 0 else { return 0 }
        return min(1.0, Double(timeSpentSeconds) / Double(estimatedSeconds))
    }

    public var formattedEstimate: String {
        return "\(estimatedMinutes)m"
    }

    public var formattedTimeSpent: String {
        let mins = timeSpentSeconds / 60
        let secs = timeSpentSeconds % 60
        if mins > 0 {
            return "\(mins)m \(secs)s"
        } else {
            return "\(secs)s"
        }
    }

    public var formattedRemainingTime: String {
        let remaining = max(0, estimatedSeconds - timeSpentSeconds)
        let mins = remaining / 60
        let secs = remaining % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
