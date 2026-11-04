import Foundation
import SwiftUI
import Observation

public enum TaskViewMode: String, CaseIterable, Sendable {
    case list = "List"
    case kanban = "Kanban"
}

public enum SidebarSection: Hashable, Sendable {
    case board(TaskBoard)
    case list(String)
}

@Observable
public final class TaskStore: @unchecked Sendable {
    public var tasks: [TaskItem] = []
    public var lists: [String] = ["General", "Work", "Research"]
    public var listColors: [String: String] = [
        "General": "orange",
        "Work": "blue",
        "Research": "purple"
    ]
    public var activeTaskId: UUID? = nil
    public var selectedTaskId: UUID? = nil
    public var selectedSection: SidebarSection = .board(.today)
    public var searchQuery: String = ""
    public var viewMode: TaskViewMode = .list
    public var deletedTaskIds: Set<UUID> = []

    private let saveURL: URL
    private let hasInitializedKey = "CocoaHasInitializedTasks"
    private var isMergingRemote = false
    private var syncDebounceTask: Task<Void, Never>? = nil

    public init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let cocoaDir = appSupport.appendingPathComponent("Cocoa", isDirectory: true)

        try? fileManager.createDirectory(at: cocoaDir, withIntermediateDirectories: true)
        self.saveURL = cocoaDir.appendingPathComponent("tasks.json")

        load()
        loadListsMetadata()
        loadDeletedTaskIds()

        let hasInitialized = UserDefaults.standard.bool(forKey: hasInitializedKey)
        let fileExists = fileManager.fileExists(atPath: saveURL.path)

        // Only seed sample tasks on the very first fresh install when no saved tasks file exists
        if !hasInitialized && !fileExists {
            loadInitialSampleTasks()
            UserDefaults.standard.set(true, forKey: hasInitializedKey)
        } else if !hasInitialized {
            UserDefaults.standard.set(true, forKey: hasInitializedKey)
        }

        if activeTaskId == nil {
            activeTaskId = tasks.first(where: { !$0.isCompleted })?.id
        }
        if selectedTaskId == nil {
            selectedTaskId = activeTaskId
        }

        // Auto-sync with Supabase in background on launch if configured
        if AppSettings.shared.isCloudSyncEnabled && AppSettings.shared.isSupabaseConfigured {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 600_000_000)
                self?.triggerCloudSync()
            }
        }
    }

    public var activeTask: TaskItem? {
        get {
            guard let id = activeTaskId else { return tasks.first(where: { !$0.isCompleted }) }
            return tasks.first(where: { $0.id == id })
        }
        set {
            if let newValue {
                if let index = tasks.firstIndex(where: { $0.id == newValue.id }) {
                    tasks[index] = newValue
                    save()
                }
            }
        }
    }

    public var selectedTask: TaskItem? {
        guard let id = selectedTaskId else { return activeTask }
        return tasks.first(where: { $0.id == id })
    }

    // MARK: - Filtered Tasks
    public var filteredTasks: [TaskItem] {
        var base: [TaskItem] = []

        switch selectedSection {
        case .board(let board):
            base = tasks.filter { $0.board == board }
        case .list(let listName):
            base = tasks.filter { $0.listName == listName && !$0.isCompleted }
        }

        if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let q = searchQuery.lowercased()
            base = base.filter { $0.title.lowercased().contains(q) || $0.notes.lowercased().contains(q) }
        }

        return base
    }

    public var todayTasks: [TaskItem] {
        return tasks.filter { $0.board == .today && !$0.isCompleted }
    }

    public var completedTasks: [TaskItem] {
        return tasks.filter { $0.isCompleted }
    }

    public func countForBoard(_ board: TaskBoard) -> Int {
        return tasks.filter { $0.board == board }.count
    }

    public func countForList(_ listName: String) -> Int {
        return tasks.filter { $0.listName == listName && !$0.isCompleted }.count
    }

    // MARK: - Actions
    public func selectTask(id: UUID) {
        selectedTaskId = id
        activeTaskId = id
    }

    public func addTask(
        title: String,
        notes: String = "",
        estimatedMinutes: Int = 25,
        priority: TaskPriority = .medium,
        listName: String? = nil,
        board: TaskBoard = .today,
        dueDate: Date? = nil
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let targetList: String
        if let listName {
            targetList = listName
        } else if case .list(let activeList) = selectedSection {
            targetList = activeList
        } else {
            targetList = "General"
        }

        let resolvedDue = dueDate ?? (board == .today ? Date() : (board == .upcoming ? Calendar.current.date(byAdding: .day, value: 1, to: Date()) : nil))

        let newTask = TaskItem(
            title: trimmed,
            notes: notes,
            estimatedMinutes: estimatedMinutes,
            priority: priority,
            listName: targetList,
            board: board,
            dueDate: resolvedDue
        )

        tasks.insert(newTask, at: 0)
        selectedTaskId = newTask.id
        if activeTaskId == nil {
            activeTaskId = newTask.id
        }
        save()
    }

    public func setDueDate(for id: UUID, date: Date?) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].dueDate = date
        if let date {
            let calendar = Calendar.current
            let startOfToday = calendar.startOfDay(for: Date())
            let startOfDue = calendar.startOfDay(for: date)
            if startOfDue <= startOfToday {
                tasks[index].board = .today
            } else {
                tasks[index].board = .upcoming
            }
            tasks[index].isCompleted = false
            tasks[index].completedAt = nil
        } else {
            tasks[index].board = .backlog
        }
        save()
    }

    public func toggleCompleted(id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].isCompleted.toggle()
        tasks[index].completedAt = tasks[index].isCompleted ? Date() : nil
        tasks[index].board = tasks[index].isCompleted ? .done : (tasks[index].dueDate != nil ? (Calendar.current.isDateInToday(tasks[index].dueDate!) ? .today : .upcoming) : .backlog)

        if tasks[index].isCompleted {
            SoundManager.shared.playSuccessSound()
        }

        if activeTaskId == id && tasks[index].isCompleted {
            activeTaskId = tasks.first(where: { !$0.isCompleted })?.id
        }
        save()
    }

    public func moveTask(id: UUID, to board: TaskBoard) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].board = board
        let calendar = Calendar.current
        switch board {
        case .today:
            tasks[index].dueDate = Date()
            tasks[index].isCompleted = false
            tasks[index].completedAt = nil
        case .upcoming:
            if let existing = tasks[index].dueDate, existing > Date() {
                // Keep future date
            } else {
                tasks[index].dueDate = calendar.date(byAdding: .day, value: 1, to: Date())
            }
            tasks[index].isCompleted = false
            tasks[index].completedAt = nil
        case .backlog:
            tasks[index].dueDate = nil
            tasks[index].isCompleted = false
            tasks[index].completedAt = nil
        case .done:
            tasks[index].isCompleted = true
            tasks[index].completedAt = Date()
        }
        save()
    }

    public func deleteTask(id: UUID) {
        tasks.removeAll(where: { $0.id == id })
        deletedTaskIds.insert(id)
        saveDeletedTaskIds()

        if activeTaskId == id {
            activeTaskId = tasks.first(where: { !$0.isCompleted })?.id
        }
        if selectedTaskId == id {
            selectedTaskId = activeTaskId
        }
        save()

        // Immediately propagate deletion to Supabase cloud
        if AppSettings.shared.isCloudSyncEnabled && AppSettings.shared.isSupabaseConfigured {
            Task {
                do {
                    try await SupabaseSyncService.shared.deleteTask(id: id)
                } catch {
                    print("[TaskStore] Cloud delete error:", error.localizedDescription)
                }
            }
        }
    }

    public func updateNotes(for taskId: UUID, notes: String) {
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        tasks[index].notes = notes
        save()
    }

    public func addSubtask(to taskId: UUID, title: String) {
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tasks[index].subtasks.append(SubtaskItem(title: trimmed))
        save()
    }

    public func toggleSubtask(in taskId: UUID, subtaskId: UUID) {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == taskId }),
              let subIndex = tasks[taskIndex].subtasks.firstIndex(where: { $0.id == subtaskId }) else { return }
        tasks[taskIndex].subtasks[subIndex].isCompleted.toggle()
        if tasks[taskIndex].subtasks[subIndex].isCompleted {
            SoundManager.shared.playSuccessSound()
        }
        save()
    }

    public func updateSubtask(in taskId: UUID, subtaskId: UUID, newTitle: String) {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == taskId }),
              let subIndex = tasks[taskIndex].subtasks.firstIndex(where: { $0.id == subtaskId }) else { return }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tasks[taskIndex].subtasks[subIndex].title = trimmed
        save()
    }

    public func deleteSubtask(in taskId: UUID, subtaskId: UUID) {
        guard let taskIndex = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        tasks[taskIndex].subtasks.removeAll(where: { $0.id == subtaskId })
        save()
    }

    public func colorForList(_ listName: String) -> Color {
        if let key = listColors[listName], let choice = ListColorChoice(rawValue: key) {
            return choice.color
        }
        let all = ListColorChoice.allCases
        let index = abs(listName.hashValue) % all.count
        return all[index].color
    }

    public func addList(name: String, color: String = "orange") {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !lists.contains(trimmed) else { return }
        lists.append(trimmed)
        listColors[trimmed] = color
        saveListsMetadata()
        save()
        scheduleListsCloudPush()
    }

    public func updateList(oldName: String, newName: String, newColor: String) {
        let trimmedOld = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNew = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOld.isEmpty, !trimmedNew.isEmpty else { return }

        // If renamed and newName already exists (other than itself), return
        if trimmedNew != trimmedOld && lists.contains(trimmedNew) {
            return
        }

        // Update list name in lists array
        if let idx = lists.firstIndex(of: trimmedOld) {
            lists[idx] = trimmedNew
        } else if !lists.contains(trimmedNew) {
            lists.append(trimmedNew)
        }

        // Update color
        listColors.removeValue(forKey: trimmedOld)
        listColors[trimmedNew] = newColor

        // Update all tasks belonging to oldName
        if trimmedNew != trimmedOld {
            for i in tasks.indices {
                if tasks[i].listName == trimmedOld {
                    tasks[i].listName = trimmedNew
                }
            }
            if case .list(let selectedList) = selectedSection, selectedList == trimmedOld {
                selectedSection = .list(trimmedNew)
            }
        }

        saveListsMetadata()
        save()
        scheduleListsCloudPush()
    }

    public func deleteList(name: String) {
        guard name != "General" else { return }
        lists.removeAll(where: { $0 == name })
        listColors.removeValue(forKey: name)
        for i in tasks.indices {
            if tasks[i].listName == name {
                tasks[i].listName = "General"
            }
        }
        if case .list(let selectedList) = selectedSection, selectedList == name {
            selectedSection = .board(.today)
        }
        saveListsMetadata()
        save()
        scheduleListsCloudPush()

        if AppSettings.shared.isCloudSyncEnabled && AppSettings.shared.isSupabaseConfigured {
            Task {
                try? await SupabaseSyncService.shared.deleteRemoteList(name: name)
            }
        }
    }

    public func scheduleListsCloudPush() {
        guard AppSettings.shared.isCloudSyncEnabled && AppSettings.shared.isSupabaseConfigured else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await SupabaseSyncService.shared.pushLists(self.lists, listColors: self.listColors)
            } catch {
                print("[TaskStore] Cloud list push notice:", error.localizedDescription)
            }
        }
    }

    public func mergeRemoteLists(_ remoteLists: [CocoaListDTO]) {
        guard !remoteLists.isEmpty else { return }
        var hasChanges = false
        for item in remoteLists {
            if !lists.contains(item.name) {
                lists.append(item.name)
                hasChanges = true
            }
            if listColors[item.name] != item.color {
                listColors[item.name] = item.color
                hasChanges = true
            }
        }
        if hasChanges {
            saveListsMetadata()
        }
    }

    public func saveListsMetadata() {
        UserDefaults.standard.set(lists, forKey: "CocoaSavedLists")
        UserDefaults.standard.set(listColors, forKey: "CocoaSavedListColors")
    }

    public func loadListsMetadata() {
        if let savedLists = UserDefaults.standard.stringArray(forKey: "CocoaSavedLists") {
            for l in savedLists where !lists.contains(l) {
                lists.append(l)
            }
        }
        if let savedColors = UserDefaults.standard.dictionary(forKey: "CocoaSavedListColors") as? [String: String] {
            for (k, v) in savedColors {
                listColors[k] = v
            }
        }
    }

    public func recordTimeSpent(id: UUID, seconds: Int) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].timeSpentSeconds += seconds
        save()
    }

    // MARK: - Persistence
    private func save() {
        do {
            let data = try JSONEncoder().encode(tasks)
            try data.write(to: saveURL, options: .atomic)
        } catch {
            print("[TaskStore] Failed to save tasks:", error)
        }
        scheduleCloudPush()
    }

    private func scheduleCloudPush() {
        guard !isMergingRemote else { return }
        guard AppSettings.shared.isCloudSyncEnabled && AppSettings.shared.isSupabaseConfigured else { return }

        syncDebounceTask?.cancel()
        syncDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled, let self else { return }
            do {
                try await SupabaseSyncService.shared.pushTasks(self.tasks)
            } catch {
                print("[TaskStore] Cloud push notice:", error.localizedDescription)
            }
        }
    }

    public func triggerCloudSync() {
        guard AppSettings.shared.isCloudSyncEnabled && AppSettings.shared.isSupabaseConfigured else { return }

        Task { [weak self] in
            guard let self else { return }
            do {
                try await SupabaseSyncService.shared.ensureSchemaMigrated()

                // 1. Sync custom lists and colors with Supabase
                try await SupabaseSyncService.shared.pushLists(self.lists, listColors: self.listColors)
                let remoteLists = try await SupabaseSyncService.shared.fetchLists()
                await MainActor.run {
                    self.mergeRemoteLists(remoteLists)
                }

                // 2. Sync tasks
                try await SupabaseSyncService.shared.pushTasks(self.tasks)
                let remote = try await SupabaseSyncService.shared.fetchTasks()
                await MainActor.run {
                    self.mergeRemoteTasks(remote)
                }
            } catch {
                print("[TaskStore] Cloud sync notice:", error.localizedDescription)
            }
        }
    }

    public func mergeRemoteTasks(_ remote: [TaskItem]) {
        guard !remote.isEmpty else { return }
        isMergingRemote = true
        defer { isMergingRemote = false }

        // Filter out tasks deleted locally to prevent resurrection
        let validRemote = remote.filter { !deletedTaskIds.contains($0.id) }

        // Also clean up remote if it contains any tasks previously deleted locally
        for r in remote where deletedTaskIds.contains(r.id) {
            Task {
                try? await SupabaseSyncService.shared.deleteTask(id: r.id)
            }
        }

        var hasChanges = false
        for r in validRemote {
            if let index = tasks.firstIndex(where: { $0.id == r.id }) {
                if tasks[index].title != r.title ||
                   tasks[index].isCompleted != r.isCompleted ||
                   tasks[index].board != r.board ||
                   tasks[index].notes != r.notes ||
                   tasks[index].priority != r.priority ||
                   tasks[index].listName != r.listName {
                    tasks[index].title = r.title
                    tasks[index].notes = r.notes
                    tasks[index].isCompleted = r.isCompleted
                    tasks[index].board = r.board
                    tasks[index].priority = r.priority
                    tasks[index].listName = r.listName
                    if r.dueDate != nil {
                        tasks[index].dueDate = r.dueDate
                    }
                    hasChanges = true
                }
            } else {
                tasks.append(r)
                if !lists.contains(r.listName) {
                    lists.append(r.listName)
                }
                hasChanges = true
            }
        }

        if hasChanges {
            do {
                let data = try JSONEncoder().encode(tasks)
                try data.write(to: saveURL, options: .atomic)
            } catch {
                print("[TaskStore] Failed to save merged tasks:", error)
            }
        }
    }

    private func saveDeletedTaskIds() {
        let stringArray = deletedTaskIds.map { $0.uuidString }
        UserDefaults.standard.set(stringArray, forKey: "CocoaDeletedTaskIds")
    }

    private func loadDeletedTaskIds() {
        if let stringArray = UserDefaults.standard.stringArray(forKey: "CocoaDeletedTaskIds") {
            self.deletedTaskIds = Set(stringArray.compactMap { UUID(uuidString: $0) })
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: saveURL.path) else { return }
        do {
            let data = try Data(contentsOf: saveURL)
            self.tasks = try JSONDecoder().decode([TaskItem].self, from: data)
            // Backfill dueDate for existing saved tasks if missing
            for i in 0..<tasks.count {
                if tasks[i].dueDate == nil {
                    if tasks[i].board == .today {
                        tasks[i].dueDate = Date()
                    } else if tasks[i].board == .upcoming {
                        tasks[i].dueDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())
                    }
                }
            }
            // collect lists
            for t in tasks {
                if !lists.contains(t.listName) {
                    lists.append(t.listName)
                }
            }
        } catch {
            print("[TaskStore] Failed to load tasks:", error)
        }
    }

    private func loadInitialSampleTasks() {
        self.tasks = [
            TaskItem(
                title: "Welcome to Cocoa 🍫",
                notes: "A powerful, native macOS focus companion engineered with Swift & SwiftUI.",
                estimatedMinutes: 15,
                priority: .high,
                listName: "General",
                subtasks: [
                    SubtaskItem(title: "Explore the Main App Dashboard", isCompleted: true),
                    SubtaskItem(title: "Click 'Focus in Notch' to try Dynamic Island", isCompleted: false),
                    SubtaskItem(title: "Test hover delay and timer protection", isCompleted: false)
                ],
                board: .today
            ),
            TaskItem(
                title: "Build Cocoa Main App UI",
                notes: "Create full sidebar, task detail inspector, and focus launcher.",
                estimatedMinutes: 25,
                priority: .high,
                listName: "Research",
                board: .today
            ),
            TaskItem(
                title: "Test Pomodoro session with audio chime",
                notes: "Start timer, observe progress bar, listen to completion sound.",
                estimatedMinutes: 25,
                priority: .medium,
                listName: "Work",
                board: .today
            ),
            TaskItem(
                title: "Plan upcoming milestone",
                notes: "Review backlog items and organize next week's focus.",
                estimatedMinutes: 30,
                priority: .low,
                listName: "General",
                board: .upcoming
            )
        ]
        save()
    }
}
