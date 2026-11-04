import SwiftUI

public struct TaskListView: View {
    @Bindable var taskStore: TaskStore
    @Bindable var timerManager: TimerManager

    @State private var newTaskTitle: String = ""
    @State private var newEstimatedMinutes: Int = 25
    @State private var newPriority: TaskPriority = .medium
    @FocusState private var isInputFocused: Bool

    public init(taskStore: TaskStore, timerManager: TimerManager) {
        self.taskStore = taskStore
        self.timerManager = timerManager
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
                    Text(sectionTitle)
                        .font(.system(size: 20, weight: .bold))

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
                    Text("No tasks found")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Add a task below or choose a different section.")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                    Spacer()
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
}
