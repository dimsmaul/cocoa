import SwiftUI

public struct KanbanBoardView: View {
    @Bindable var taskStore: TaskStore
    @Bindable var timerManager: TimerManager
    public var onOpenDetail: (TaskItem) -> Void

    @State private var addingToBoard: TaskBoard? = nil
    @State private var newQuickTitle: String = ""

    public init(
        taskStore: TaskStore,
        timerManager: TimerManager,
        onOpenDetail: @escaping (TaskItem) -> Void
    ) {
        self.taskStore = taskStore
        self.timerManager = timerManager
        self.onOpenDetail = onOpenDetail
    }

    private var sectionTitle: String {
        switch taskStore.selectedSection {
        case .board(let board): return board.rawValue
        case .list(let list): return list
        case .stats: return "Focus Stats"
        }
    }

    private var sectionIcon: String {
        switch taskStore.selectedSection {
        case .board(let board): return board.iconName
        case .list: return "folder.fill"
        case .stats: return "chart.bar.fill"
        }
    }

    private var sectionColor: Color {
        switch taskStore.selectedSection {
        case .board(let board): return boardColor(for: board)
        case .list(let list): return taskStore.colorForList(list)
        case .stats: return .orange
        }
    }

    private func tasksForColumn(board: TaskBoard) -> [TaskItem] {
        var base = taskStore.tasks.filter { $0.board == board }

        // Filter by active project/list if a list is selected in the sidebar
        if case .list(let listName) = taskStore.selectedSection {
            base = base.filter { $0.listName == listName }
        }

        // Apply search query if typed
        if !taskStore.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let q = taskStore.searchQuery.lowercased()
            base = base.filter { $0.title.lowercased().contains(q) || $0.notes.lowercased().contains(q) }
        }

        return base
    }

    private var totalTasksCount: Int {
        TaskBoard.allCases.reduce(0) { $0 + tasksForColumn(board: $1).count }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: sectionIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(sectionColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(sectionTitle)
                            .font(.system(size: 20, weight: .bold))

                        Text("\(totalTasksCount) tasks")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Search Bar
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("Search tasks...", text: $taskStore.searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !taskStore.searchQuery.isEmpty {
                        Button(action: { taskStore.searchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(width: 180)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            // Horizontal Kanban Columns
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 16) {
                    // The 4 Kanban boards: Backlog, Upcoming, Today, Done
                    kanbanColumn(board: .backlog)
                    kanbanColumn(board: .upcoming)
                    kanbanColumn(board: .today)
                    kanbanColumn(board: .done)
                }
                .padding(16)
            }
            .background(Color.primary.opacity(0.015))
        }
    }

    // MARK: - Kanban Column
    private func kanbanColumn(board: TaskBoard) -> some View {
        let tasks = tasksForColumn(board: board)

        return VStack(alignment: .leading, spacing: 10) {
            // Column Header
            HStack(spacing: 8) {
                Image(systemName: board.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(boardColor(for: board))

                Text(board.rawValue)
                    .font(.system(size: 13, weight: .bold))

                Text("\(tasks.count)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())

                Spacer()

                Button(action: {
                    if addingToBoard == board {
                        addingToBoard = nil
                    } else {
                        addingToBoard = board
                        newQuickTitle = ""
                    }
                }) {
                    Image(systemName: addingToBoard == board ? "xmark" : "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(5)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Add task to \(board.rawValue)")
            }
            .padding(.horizontal, 4)

            // Quick Add Input Box (if open for this column)
            if addingToBoard == board {
                HStack(spacing: 6) {
                    TextField("New task title...", text: $newQuickTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .onSubmit {
                            submitQuickTask(to: board)
                        }

                    Button("Add") {
                        submitQuickTask(to: board)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange)
                }
                .padding(8)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Cards Container with Drop Destination
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    if tasks.isEmpty && addingToBoard != board {
                        VStack(spacing: 6) {
                            Text("No tasks")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    } else {
                        ForEach(tasks) { task in
                            kanbanCard(task: task)
                                .draggable(task.id.uuidString)
                        }
                    }
                }
            }
        }
        .frame(width: 260)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.primary.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
        .dropDestination(for: String.self) { items, location in
            guard let firstIdString = items.first,
                  let taskId = UUID(uuidString: firstIdString) else { return false }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                taskStore.moveTask(id: taskId, to: board)
                timerManager.syncWithActiveTask()
            }
            return true
        }
    }

    // MARK: - Kanban Card View
    private func kanbanCard(task: TaskItem) -> some View {
        return VStack(alignment: .leading, spacing: 8) {
            // Top Row: Checkbox, Title & Move Menu
            HStack(alignment: .top, spacing: 8) {
                Button(action: {
                    taskStore.toggleCompleted(id: task.id)
                    timerManager.syncWithActiveTask()
                }) {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15))
                        .foregroundStyle(task.isCompleted ? Color.green : Color.secondary)
                }
                .buttonStyle(.plain)

                Text(task.title)
                    .font(.system(size: 13, weight: .medium))
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? Color.secondary : Color.primary)
                    .lineLimit(2)

                Spacer()

                // Move to another board menu
                Menu {
                    Button("Open Details...") {
                        taskStore.selectTask(id: task.id)
                        timerManager.syncWithActiveTask()
                        onOpenDetail(task)
                    }
                    Divider()

                    ForEach(TaskBoard.allCases, id: \.self) { targetBoard in
                        if targetBoard != task.board {
                            Button("Move to \(targetBoard.rawValue)") {
                                withAnimation {
                                    taskStore.moveTask(id: task.id, to: targetBoard)
                                    timerManager.syncWithActiveTask()
                                }
                            }
                        }
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        taskStore.deleteTask(id: task.id)
                        timerManager.syncWithActiveTask()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            // Notes preview (if any)
            if let preview = task.notesPreview {
                Text(preview)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Bottom Badges: List Group, Subtasks, Priority, Estimate
            HStack(spacing: 6) {
                // List Group Badge with custom folder color
                listBadge(for: task.listName)

                TaskScheduleBadges(task: task)

                if !task.subtasks.isEmpty {
                    let completed = task.subtasks.filter { $0.isCompleted }.count
                    HStack(spacing: 3) {
                        Image(systemName: "checklist")
                            .font(.system(size: 9))
                        Text("\(completed)/\(task.subtasks.count)")
                            .font(.system(size: 9, design: .monospaced))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(Capsule())
                }

                Spacer()

                // Priority
                Text(task.priority.rawValue)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(priorityColor(task.priority))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(priorityColor(task.priority).opacity(0.12))
                    .clipShape(Capsule())

                // Estimate
                HStack(spacing: 2) {
                    Image(systemName: "timer")
                        .font(.system(size: 9))
                    Text(task.formattedEstimate)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            taskStore.selectTask(id: task.id)
            timerManager.syncWithActiveTask()
            onOpenDetail(task)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                )
        )
    }

    private func submitQuickTask(to board: TaskBoard) {
        let trimmed = newQuickTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let targetList: String? = {
            if case .list(let listName) = taskStore.selectedSection {
                return listName
            }
            return nil
        }()

        taskStore.addTask(title: trimmed, listName: targetList, board: board)
        newQuickTitle = ""
        addingToBoard = nil
        timerManager.syncWithActiveTask()
    }

    private func boardColor(for board: TaskBoard) -> Color {
        switch board {
        case .inbox: return Color(red: 0.35, green: 0.55, blue: 0.95)
        case .today: return .orange
        case .upcoming: return .blue
        case .backlog: return .purple
        case .done: return .green
        }
    }

    private func priorityColor(_ priority: TaskPriority) -> Color {
        switch priority {
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }

    private func listBadge(for listName: String) -> some View {
        let color = taskStore.colorForList(listName)
        return HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 4.5, height: 4.5)
            Text(listName)
                .font(.system(size: 8.5, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}
