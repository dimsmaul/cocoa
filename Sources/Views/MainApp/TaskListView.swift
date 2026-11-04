import SwiftUI

public struct TaskListView: View {
    @Bindable var taskStore: TaskStore
    @Bindable var timerManager: TimerManager
    public var onOpenDetail: ((TaskItem) -> Void)? = nil

    @State private var newTaskTitle: String = ""
    @State private var newEstimatedMinutes: Int = 25
    @State private var newPriority: TaskPriority = .medium
    @State private var editingList: EditableListTarget? = nil
    @FocusState private var isInputFocused: Bool

    public init(
        taskStore: TaskStore,
        timerManager: TimerManager,
        onOpenDetail: ((TaskItem) -> Void)? = nil
    ) {
        self.taskStore = taskStore
        self.timerManager = timerManager
        self.onOpenDetail = onOpenDetail
    }

    private var sectionTitle: String {
        switch taskStore.selectedSection {
        case .board(let board): return board.rawValue
        case .list(let list): return list
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(sectionTitle)
                            .font(.system(size: 20, weight: .bold))

                        if case .list(let listName) = taskStore.selectedSection {
                            Button(action: {
                                editingList = EditableListTarget(
                                    name: listName,
                                    color: taskStore.listColors[listName] ?? "orange"
                                )
                            }) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(4)
                                    .background(Color.primary.opacity(0.06))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help("Edit List '\(listName)'")
                        }
                    }

                    Text("\(taskStore.filteredTasks.count) tasks")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
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

            // Task List
            if taskStore.filteredTasks.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text(isInboxSection ? "Inbox Zero" : "No tasks found")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(isInboxSection ? "All caught up! Add a new task below." : "Add a task below or choose a different section.")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            } else if isInboxSection {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if !overdueTasks.isEmpty {
                            inboxGroupView(
                                title: "Overdue",
                                icon: "exclamationmark.circle.fill",
                                color: .red,
                                tasks: overdueTasks
                            )
                        }

                        inboxGroupView(
                            title: todaySectionTitle,
                            icon: "sun.max.fill",
                            color: .orange,
                            tasks: todayGroupTasks
                        )

                        if !upcomingGroupTasks.isEmpty {
                            inboxGroupView(
                                title: "Upcoming",
                                icon: "calendar",
                                color: .purple,
                                tasks: upcomingGroupTasks
                            )
                        }

                        if !noDateTasks.isEmpty {
                            inboxGroupView(
                                title: "No Date",
                                icon: "tray.fill",
                                color: .secondary,
                                tasks: noDateTasks
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(taskStore.filteredTasks) { task in
                            taskCard(task: task)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }

            Divider()

            // Quick Add Task Bar
            quickAddBar
                .padding(14)
                .background(Color.primary.opacity(0.02))
        }
        .sheet(item: $editingList) { target in
            NewListDialogView(
                taskStore: taskStore,
                mode: .edit(originalName: target.name, currentColor: target.color),
                onClose: {
                    editingList = nil
                }
            )
        }
    }

    private func taskCard(task: TaskItem) -> some View {
        let isSelected = task.id == taskStore.selectedTaskId

        return HStack(spacing: 12) {
            // Checkbox
            Button(action: {
                taskStore.toggleCompleted(id: task.id)
                timerManager.syncWithActiveTask()
            }) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(task.isCompleted ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)

            // Title & Details
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 13, weight: .regular))
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? Color.secondary : Color.primary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if !task.notes.isEmpty {
                        Text(task.notes)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if !task.subtasks.isEmpty {
                        let completedCount = task.subtasks.filter { $0.isCompleted }.count
                        HStack(spacing: 3) {
                            Image(systemName: "checklist")
                                .font(.system(size: 10))
                            Text("\(completedCount)/\(task.subtasks.count)")
                                .font(.system(size: 10, design: .monospaced))
                        }
                        .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            // List Group Badge with custom folder color
            listBadge(for: task.listName)

            // Priority Pill
            Text(task.priority.rawValue)
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(priorityColor(task.priority).opacity(0.12))
                .foregroundStyle(priorityColor(task.priority))
                .clipShape(Capsule())

            // Time estimate badge
            HStack(spacing: 3) {
                Image(systemName: "timer")
                    .font(.system(size: 10))
                Text(task.formattedEstimate)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Delete button
            Button(action: {
                taskStore.deleteTask(id: task.id)
                timerManager.syncWithActiveTask()
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Delete Task")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.primary.opacity(0.08) : Color.primary.opacity(0.03))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            taskStore.selectTask(id: task.id)
            timerManager.syncWithActiveTask()
            onOpenDetail?(task)
        }
    }

    private var quickAddBar: some View {
        HStack(spacing: 10) {
            TextField("Add a new task and press Enter...", text: $newTaskTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isInputFocused)
                .onSubmit {
                    submitTask()
                }

            // Estimate picker
            Menu {
                Button("15 mins") { newEstimatedMinutes = 15 }
                Button("25 mins (Pomodoro)") { newEstimatedMinutes = 25 }
                Button("45 mins") { newEstimatedMinutes = 45 }
                Button("60 mins") { newEstimatedMinutes = 60 }
            } label: {
                Text("\(newEstimatedMinutes)m")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Priority picker
            Menu {
                ForEach(TaskPriority.allCases, id: \.self) { p in
                    Button(p.rawValue) { newPriority = p }
                }
            } label: {
                Text(newPriority.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(priorityColor(newPriority))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(priorityColor(newPriority).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button(action: submitTask) {
                Text("Add")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1.0))
                    .foregroundStyle(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.white.opacity(0.6) : Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func submitTask() {
        guard !newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        taskStore.addTask(
            title: newTaskTitle,
            estimatedMinutes: newEstimatedMinutes,
            priority: newPriority
        )
        newTaskTitle = ""
        timerManager.syncWithActiveTask()
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
        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(listName)
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Inbox Grouping Helpers
    private var isInboxSection: Bool {
        if case .board(let board) = taskStore.selectedSection, board == .inbox {
            return true
        }
        return false
    }

    private var todaySectionTitle: String {
        let now = Date()
        let dayMonth = DateFormatter()
        dayMonth.dateFormat = "d MMM"
        let weekday = DateFormatter()
        weekday.dateFormat = "EEEE"
        return "\(dayMonth.string(from: now)) . Today . \(weekday.string(from: now))"
    }

    private var overdueTasks: [TaskItem] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return taskStore.filteredTasks.filter { task in
            guard let due = task.dueDate else { return false }
            return due < startOfToday && !task.isCompleted
        }
    }

    private var todayGroupTasks: [TaskItem] {
        return taskStore.filteredTasks.filter { task in
            if let due = task.dueDate {
                return Calendar.current.isDateInToday(due) && !task.isCompleted
            } else {
                return (task.board == .today || task.board == .inbox) && !task.isCompleted
            }
        }
    }

    private var upcomingGroupTasks: [TaskItem] {
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) else { return [] }
        return taskStore.filteredTasks.filter { task in
            if let due = task.dueDate {
                return due >= tomorrow && !task.isCompleted
            } else {
                return task.board == .upcoming && !task.isCompleted
            }
        }
    }

    private var noDateTasks: [TaskItem] {
        let overdueIds = Set(overdueTasks.map(\.id))
        let todayIds = Set(todayGroupTasks.map(\.id))
        let upcomingIds = Set(upcomingGroupTasks.map(\.id))
        return taskStore.filteredTasks.filter { task in
            !task.isCompleted && !overdueIds.contains(task.id) && !todayIds.contains(task.id) && !upcomingIds.contains(task.id)
        }
    }

    private func inboxGroupView(
        title: String,
        icon: String,
        color: Color,
        tasks: [TaskItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Group Header with clean line
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)

                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.primary)

                Text("\(tasks.count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(color.opacity(0.12))
                    .clipShape(Capsule())

                // Clean divider line extending to the right
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)
            }
            .padding(.top, 8)
            .padding(.bottom, 2)

            if tasks.isEmpty {
                Text("No tasks")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 12)
                    .padding(.vertical, 4)
            } else {
                ForEach(tasks) { task in
                    taskCard(task: task)
                }
            }
        }
    }
}
