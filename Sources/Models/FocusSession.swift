import Foundation

public struct FocusSession: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let taskId: UUID
    public let taskTitle: String
    public let startedAt: Date
    public var seconds: Int

    public init(id: UUID = UUID(), taskId: UUID, taskTitle: String, startedAt: Date, seconds: Int) {
        self.id = id
        self.taskId = taskId
        self.taskTitle = taskTitle
        self.startedAt = startedAt
        self.seconds = seconds
    }
}

/// Builds one session per uninterrupted run of the timer on a single task.
public struct FocusSessionTracker: Equatable, Sendable {
    public private(set) var current: FocusSession?

    public init() {}

    /// Counts one second. Returns the previous session if the active task changed.
    public mutating func tick(taskId: UUID, taskTitle: String, now: Date) -> FocusSession? {
        if var session = current, session.taskId == taskId {
            session.seconds += 1
            current = session
            return nil
        }
        let finished = current
        current = FocusSession(taskId: taskId, taskTitle: taskTitle, startedAt: now, seconds: 1)
        return finished
    }

    public mutating func finish() -> FocusSession? {
        defer { current = nil }
        return current
    }
}

public struct DailyFocus: Identifiable, Equatable, Sendable {
    public let day: Date
    public let seconds: Int

    public var id: Date { day }
}

public struct EstimateComparison: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let estimatedSeconds: Int
    public let actualSeconds: Int
}

public enum FocusStats {
    /// Oldest day first. Days without focus are included with zero seconds.
    public static func lastSevenDays(sessions: [FocusSession], now: Date, calendar: Calendar = .current) -> [DailyFocus] {
        let today = calendar.startOfDay(for: now)
        return (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let seconds = sessions
                .filter { calendar.isDate($0.startedAt, inSameDayAs: day) }
                .reduce(0) { $0 + $1.seconds }
            return DailyFocus(day: day, seconds: seconds)
        }
    }

    public static func secondsToday(sessions: [FocusSession], now: Date, calendar: Calendar = .current) -> Int {
        sessions
            .filter { calendar.isDate($0.startedAt, inSameDayAs: now) }
            .reduce(0) { $0 + $1.seconds }
    }

    public static func secondsThisWeek(sessions: [FocusSession], now: Date, calendar: Calendar = .current) -> Int {
        sessions
            .filter { calendar.isDate($0.startedAt, equalTo: now, toGranularity: .weekOfYear) }
            .reduce(0) { $0 + $1.seconds }
    }

    /// Tasks completed in the last seven days, newest first.
    public static func estimateVsActual(tasks: [TaskItem], now: Date, calendar: Calendar = .current) -> [EstimateComparison] {
        guard let cutoff = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) else { return [] }
        return tasks
            .filter { $0.isCompleted && ($0.completedAt ?? .distantPast) >= cutoff }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
            .map {
                EstimateComparison(
                    id: $0.id,
                    title: $0.title,
                    estimatedSeconds: $0.estimatedSeconds,
                    actualSeconds: $0.timeSpentSeconds
                )
            }
    }

    public static func formatted(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        if minutes > 0 {
            return "\(minutes)m"
        }
        return "\(seconds)s"
    }
}

/// One JSON session per line, so a damaged line costs that session only and saving never
/// rewrites existing history.
public struct FocusSessionLog: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() -> [FocusSession] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        return data
            .split(separator: UInt8(ascii: "\n"))
            .compactMap { try? decoder.decode(FocusSession.self, from: Data($0)) }
    }

    public func append(_ session: FocusSession) throws {
        var line = try JSONEncoder().encode(session)
        line.append(UInt8(ascii: "\n"))

        if !FileManager.default.fileExists(atPath: url.path) {
            try line.write(to: url, options: .atomic)
            return
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }
}
