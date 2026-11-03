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
    case today = "Today"
    case upcoming = "Upcoming"
    case backlog = "Backlog"
    case done = "Completed"

    public var iconName: String {
        switch self {
        case .today: return "sun.max.fill"
        case .upcoming: return "calendar"
        case .backlog: return "tray.full.fill"
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

    public init(id: UUID = UUID(), title: String, isCompleted: Bool = false) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
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
    public var completedAt: Date?
    public var createdAt: Date
    public var board: TaskBoard
    public var dueDate: Date?

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
        completedAt: Date? = nil,
        createdAt: Date = Date(),
        board: TaskBoard = .today,
        dueDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.estimatedMinutes = estimatedMinutes
        self.timeSpentSeconds = timeSpentSeconds
        self.isCompleted = isCompleted
        self.priority = priority
        self.listName = listName
        self.subtasks = subtasks
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
