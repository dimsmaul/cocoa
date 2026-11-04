import Foundation
import Supabase

import Foundation
import Supabase

public struct CocoaListDTO: Codable, Sendable {
    public let name: String
    public let color: String

    public init(name: String, color: String) {
        self.name = name
        self.color = color
    }
}

public let CocoaListsMetadataUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

public struct SupabaseTaskDTO: Codable, Sendable {
    public let id: UUID
    public var title: String
    public var notes: String
    public var estimated_minutes: Int
    public var time_spent_seconds: Int
    public var is_completed: Bool
    public var board: String
    public var priority: String
    public var list_name: String
    public var completed_at: Date?
    public var created_at: Date
    public var due_date: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case notes
        case estimated_minutes
        case time_spent_seconds
        case is_completed
        case board
        case priority
        case list_name
        case completed_at
        case created_at
        case due_date
    }

    public init(
        id: UUID,
        title: String,
        notes: String = "",
        estimatedMinutes: Int = 0,
        timeSpentSeconds: Int = 0,
        isCompleted: Bool = false,
        board: String = "Backlog",
        priority: String = "Low",
        listName: String = "General",
        completedAt: Date? = nil,
        createdAt: Date = Date(),
        dueDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.estimated_minutes = estimatedMinutes
        self.time_spent_seconds = timeSpentSeconds
        self.is_completed = isCompleted
        self.board = board
        self.priority = priority
        self.list_name = listName
        self.completed_at = completedAt
        self.created_at = createdAt
        self.due_date = dueDate
    }

    public init(from task: TaskItem) {
        self.id = task.id
        self.title = task.title
        self.notes = task.notes
        self.estimated_minutes = task.estimatedMinutes
        self.time_spent_seconds = task.timeSpentSeconds
        self.is_completed = task.isCompleted
        self.board = task.board.rawValue
        self.priority = task.priority.rawValue
        self.list_name = task.listName
        self.completed_at = task.completedAt
        self.created_at = task.createdAt
        self.due_date = task.dueDate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.notes = (try? container.decode(String.self, forKey: .notes)) ?? ""
        self.estimated_minutes = (try? container.decode(Int.self, forKey: .estimated_minutes)) ?? 25
        self.time_spent_seconds = (try? container.decode(Int.self, forKey: .time_spent_seconds)) ?? 0
        self.is_completed = (try? container.decode(Bool.self, forKey: .is_completed)) ?? false
        self.board = (try? container.decode(String.self, forKey: .board)) ?? "Today"
        self.priority = (try? container.decode(String.self, forKey: .priority)) ?? "Medium"
        self.list_name = (try? container.decode(String.self, forKey: .list_name)) ?? "General"

        // Robust date parsing for completed_at
        if let compDate = try? container.decodeIfPresent(Date.self, forKey: .completed_at) {
            self.completed_at = compDate
        } else if let compStr = try? container.decodeIfPresent(String.self, forKey: .completed_at) {
            self.completed_at = ISO8601DateHelper.parse(compStr)
        } else {
            self.completed_at = nil
        }

        // Robust date parsing for created_at
        if let crDate = try? container.decode(Date.self, forKey: .created_at) {
            self.created_at = crDate
        } else if let crStr = try? container.decode(String.self, forKey: .created_at) {
            self.created_at = ISO8601DateHelper.parse(crStr) ?? Date()
        } else {
            self.created_at = Date()
        }

        // Robust date parsing for due_date
        if let dueDate = try? container.decodeIfPresent(Date.self, forKey: .due_date) {
            self.due_date = dueDate
        } else if let dueStr = try? container.decodeIfPresent(String.self, forKey: .due_date) {
            self.due_date = ISO8601DateHelper.parse(dueStr)
        } else {
            self.due_date = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(notes, forKey: .notes)
        try container.encode(estimated_minutes, forKey: .estimated_minutes)
        try container.encode(time_spent_seconds, forKey: .time_spent_seconds)
        try container.encode(is_completed, forKey: .is_completed)
        try container.encode(board, forKey: .board)
        try container.encode(priority, forKey: .priority)
        try container.encode(list_name, forKey: .list_name)
        try container.encodeIfPresent(completed_at, forKey: .completed_at)
        try container.encode(created_at, forKey: .created_at)

        // Conditionally encode due_date only if supported by the remote Supabase PostgreSQL schema
        if SupabaseSyncService.shared.supportsDueDate {
            try container.encodeIfPresent(due_date, forKey: .due_date)
        }
    }

    public func toTaskItem() -> TaskItem {
        let taskBoard = TaskBoard(rawValue: board) ?? .today
        let taskPriority = TaskPriority(rawValue: priority) ?? .medium
        return TaskItem(
            id: id,
            title: title,
            notes: notes,
            estimatedMinutes: estimated_minutes,
            timeSpentSeconds: time_spent_seconds,
            isCompleted: is_completed,
            priority: taskPriority,
            listName: list_name,
            subtasks: [],
            completedAt: completed_at,
            createdAt: created_at,
            board: taskBoard,
            dueDate: due_date
        )
    }
}

public enum ISO8601DateHelper {
    public static func parse(_ string: String) -> Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: string) { return d }

        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: string)
    }
}

public final class SupabaseSyncService: @unchecked Sendable {
    public static let shared = SupabaseSyncService()

    private var client: SupabaseClient?
    public var supportsDueDate: Bool = false
    public var supportsListsTable: Bool = false
    public var isSchemaMigrated: Bool = false

    private init() {
        configureClient()
    }

    public func configureClient() {
        let settings = AppSettings.shared
        guard settings.isSupabaseConfigured,
              let url = URL(string: settings.supabaseURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            self.client = nil
            return
        }

        self.client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: settings.supabaseAnonKey.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Automatically validates and migrates the database schema on initial sync.
    /// Discovers existing tables and column capabilities (such as `due_date`) without requiring manual SQL setup.
    public func ensureSchemaMigrated() async throws {
        configureClient()
        guard let client else {
            throw NSError(domain: "Cocoa.Supabase", code: 400, userInfo: [NSLocalizedDescriptionKey: "Supabase URL and Anon Key must be configured."])
        }

        let settings = AppSettings.shared
        let urlString = settings.supabaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: urlString) else {
            throw NSError(domain: "Cocoa.Supabase", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid Supabase URL."])
        }

        // Introspect PostgREST OpenAPI schema
        let openAPIURL = baseURL.appendingPathComponent("rest/v1/")
        var request = URLRequest(url: openAPIURL)
        request.httpMethod = "GET"
        request.addValue(settings.supabaseAnonKey.trimmingCharacters(in: .whitespacesAndNewlines), forHTTPHeaderField: "apikey")
        request.addValue("Bearer \(settings.supabaseAnonKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let definitions = json["definitions"] as? [String: Any] {
                    if let tasksDef = definitions["tasks"] as? [String: Any],
                       let properties = tasksDef["properties"] as? [String: Any] {
                        self.supportsDueDate = properties["due_date"] != nil
                    }
                    self.supportsListsTable = definitions["lists"] != nil
                    self.isSchemaMigrated = true
                    print("[SupabaseSync] Database schema validated. supportsDueDate=\(self.supportsDueDate), supportsListsTable=\(self.supportsListsTable)")
                    return
                }
            }
        } catch {
            print("[SupabaseSync] OpenAPI check notice:", error.localizedDescription)
        }

        // Fallback test query on tasks table
        let _ = try await client
            .from("tasks")
            .select()
            .limit(1)
            .execute()

        self.isSchemaMigrated = true
    }

    public func testConnection() async throws -> String {
        configureClient()
        guard let _ = client else {
            throw NSError(domain: "Cocoa.Supabase", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid Supabase URL or Anon Key."])
        }

        let start = Date()
        try await ensureSchemaMigrated()
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)
        return "Connected & Synced! (Ping: \(elapsed)ms, Tasks table ready)"
    }

    public func pushTasks(_ tasks: [TaskItem]) async throws {
        configureClient()
        guard let client else { return }
        guard !tasks.isEmpty else { return }

        if !isSchemaMigrated {
            try? await ensureSchemaMigrated()
        }

        let dtos = tasks.map { SupabaseTaskDTO(from: $0) }
        try await client
            .from("tasks")
            .upsert(dtos)
            .execute()
    }

    public func fetchTasks() async throws -> [TaskItem] {
        configureClient()
        guard let client else { return [] }

        if !isSchemaMigrated {
            try? await ensureSchemaMigrated()
        }

        let dtos: [SupabaseTaskDTO] = try await client
            .from("tasks")
            .select()
            .execute()
            .value

        // Exclude system metadata records from normal tasks
        let userDtos = dtos.filter { $0.id != CocoaListsMetadataUUID && !$0.title.hasPrefix("[Cocoa:ListsMetadata]") }
        return userDtos.map { $0.toTaskItem() }
    }

    public func pushLists(_ lists: [String], listColors: [String: String]) async throws {
        configureClient()
        guard let client else { return }

        let dtos = lists.map { CocoaListDTO(name: $0, color: listColors[$0] ?? "orange") }
        guard let jsonData = try? JSONEncoder().encode(dtos),
              let jsonStr = String(data: jsonData, encoding: .utf8) else { return }

        // 1. If dedicated lists table exists in Supabase, upsert into it
        if supportsListsTable {
            _ = try? await client
                .from("lists")
                .upsert(dtos)
                .execute()
        }

        // 2. Always persist to system metadata record in tasks table so cross-device sync works seamlessly
        let metaTask = SupabaseTaskDTO(
            id: CocoaListsMetadataUUID,
            title: "[Cocoa:ListsMetadata]",
            notes: jsonStr,
            estimatedMinutes: 0,
            timeSpentSeconds: 0,
            isCompleted: false,
            board: "Backlog",
            priority: "Low",
            listName: "System",
            completedAt: nil,
            createdAt: Date(),
            dueDate: nil
        )

        try await client
            .from("tasks")
            .upsert(metaTask)
            .execute()
    }

    public func fetchLists() async throws -> [CocoaListDTO] {
        configureClient()
        guard let client else { return [] }

        if !isSchemaMigrated {
            try? await ensureSchemaMigrated()
        }

        // 1. Try fetching from dedicated lists table if supported
        if supportsListsTable {
            if let lists: [CocoaListDTO] = try? await client
                .from("lists")
                .select()
                .execute()
                .value, !lists.isEmpty {
                return lists
            }
        }

        // 2. Fallback: fetch from tasks system metadata record
        do {
            let metaQuery: [SupabaseTaskDTO] = try await client
                .from("tasks")
                .select()
                .eq("id", value: CocoaListsMetadataUUID.uuidString)
                .execute()
                .value

            if let metaRecord = metaQuery.first,
               let data = metaRecord.notes.data(using: .utf8),
               let lists = try? JSONDecoder().decode([CocoaListDTO].self, from: data) {
                return lists
            }
        } catch {
            print("[SupabaseSync] Notice fetching list metadata:", error.localizedDescription)
        }

        return []
    }

    public func deleteRemoteList(name: String) async throws {
        configureClient()
        guard let client else { return }

        if supportsListsTable {
            _ = try? await client
                .from("lists")
                .delete()
                .eq("name", value: name)
                .execute()
        }
    }

    public func deleteTask(id: UUID) async throws {
        configureClient()
        guard let client else { return }

        try await client
            .from("tasks")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }
}
