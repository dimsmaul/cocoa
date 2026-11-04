import SwiftUI

public struct TaskModalDialogView: View {
    public let task: TaskItem
    @Bindable var taskStore: TaskStore
    @Bindable var timerManager: TimerManager
    public var onClose: () -> Void
    public var onLaunchNotchMode: () -> Void
    public var onLaunchTowerMode: () -> Void

    @State private var newSubtaskTitle: String = ""
    @State private var editingSubtaskId: UUID? = nil
    @State private var editingSubtaskTitle: String = ""
    @FocusState private var isSubtaskEditFocused: Bool

    public init(
        task: TaskItem,
        taskStore: TaskStore,
        timerManager: TimerManager,
        onClose: @escaping () -> Void,
        onLaunchNotchMode: @escaping () -> Void,
        onLaunchTowerMode: @escaping () -> Void
    ) {
        self.task = task
        self.taskStore = taskStore
        self.timerManager = timerManager
        self.onClose = onClose
        self.onLaunchNotchMode = onLaunchNotchMode
        self.onLaunchTowerMode = onLaunchTowerMode
    }

    private var currentTask: TaskItem {
        taskStore.tasks.first(where: { $0.id == task.id }) ?? task
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Modal Header Bar
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "list.clipboard")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text("Task Details")
                        .font(.system(size: 13, weight: .bold))
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            // Scrollable Detail Body
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Focus Session Hero Card
                    focusSessionCard(task: currentTask)

                    // Core Task Fields (Title, Notes, Board, Priority, List)
                    taskFieldsSection(task: currentTask)

                    Divider()

                    // Subtasks Checklist
                    subtasksSection(task: currentTask)
                }
                .padding(20)
            }
        }
        .frame(width: 540, height: 620)
        .background(.regularMaterial)
    }

    // MARK: - Focus Session Hero Card
    private func focusSessionCard(task: TaskItem) -> some View {
        let isCurrentActive = timerManager.isRunning && taskStore.activeTaskId == task.id

        return VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("FOCUS TIMER")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(isCurrentActive ? "Session in Progress" : (timerManager.state == .paused && taskStore.activeTaskId == task.id ? "Session Paused" : "Ready to Focus"))
                        .font(.system(size: 12, weight: .semibold))
                }

                Spacer()

                // Mode switch buttons
                HStack(spacing: 8) {
                    Button(action: onLaunchNotchMode) {
                        HStack(spacing: 4) {
                            Image(systemName: "menubar.arrow.up.rectangle")
                                .font(.system(size: 10))
                            Text("Notch Pill")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Minimize to MacBook Notch Dynamic Island")

                    Button(action: onLaunchTowerMode) {
                        HStack(spacing: 4) {
                            Image(systemName: "rectangle.inset.filled.and.cursorarrow")
                                .font(.system(size: 10))
                            Text("Tower")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.08))
                        .foregroundStyle(.primary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Pop out as Floating Desktop Card")
                }
            }

            // Big Timer Display
            HStack(spacing: 24) {
                ZStack {
                    ProgressRing(
                        progress: timerManager.progress,
                        lineWidth: 6,
                        ringColor: isCurrentActive ? .orange : .secondary
                    )
                    .frame(width: 85, height: 85)

                    VStack(spacing: 2) {
                        Text(timerManager.formattedTime)
                            .font(.system(size: 19, weight: .bold, design: .monospaced))
                            .foregroundStyle(isCurrentActive ? Color.orange : Color.primary)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    // Play / Pause Button
                    Button(action: {
                        if taskStore.activeTaskId != task.id {
                            taskStore.selectTask(id: task.id)
                            timerManager.syncWithActiveTask()
                        }
                        timerManager.toggle()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: isCurrentActive ? "pause.fill" : "play.fill")
                                .font(.system(size: 13, weight: .bold))
                            Text(isCurrentActive ? "Pause Focus" : "Start Focus")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.orange)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 8) {
                        Button(action: { timerManager.reset() }) {
                            Text("Reset")
                                .font(.system(size: 11, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(Color.secondary.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .contentShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            timerManager.completeCurrentSession()
                        }) {
                            Text("Mark Done")
                                .font(.system(size: 11, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(Color.green.opacity(0.15))
                                .foregroundStyle(.green)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .contentShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Text("Time Spent: \(task.formattedTimeSpent)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Estimate: \(task.formattedEstimate)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - Task Fields Section
    private func taskFieldsSection(task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Task Title
            VStack(alignment: .leading, spacing: 4) {
                Text("TITLE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)

                TextField("Task Title", text: Binding(
                    get: { task.title },
                    set: { newTitle in
                        if let index = taskStore.tasks.firstIndex(where: { $0.id == task.id }) {
                            taskStore.tasks[index].title = newTitle
                        }
                    }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .semibold))
                .padding(.vertical, 4)
            }

            // Task Notes / Description (Native Rich Text via RichTextKit)
            VStack(alignment: .leading, spacing: 4) {
                Text("NOTES")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)

                NativeRichTextEditor(
                    text: Binding(
                        get: { task.notes },
                        set: { newNotes in
                            taskStore.updateNotes(for: task.id, notes: newNotes)
                        }
                    ),
                    taskId: task.id,
                    baseFontSize: 14,
                    minHeight: 120
                )
            }

            // Attributes Grid (Date, Priority, List)
            VStack(spacing: 8) {
                HStack {
                    Text("Date")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    TaskDatePickerButton(task: task, taskStore: taskStore, width: 132)
                }

                HStack {
                    Text("Priority")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { task.priority },
                        set: { newPriority in
                            if let index = taskStore.tasks.firstIndex(where: { $0.id == task.id }) {
                                taskStore.tasks[index].priority = newPriority
                            }
                        }
                    )) {
                        ForEach(TaskPriority.allCases, id: \.self) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                }

                HStack {
                    Text("List / Project")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { task.listName },
                        set: { newList in
                            if let index = taskStore.tasks.firstIndex(where: { $0.id == task.id }) {
                                taskStore.tasks[index].listName = newList
                            }
                        }
                    )) {
                        ForEach(taskStore.lists, id: \.self) { l in
                            Text(l).tag(l)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                }
            }
        }
    }

    // MARK: - Subtasks Section
    private func subtasksSection(task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SUBTASKS (\(task.subtasks.filter { $0.isCompleted }.count)/\(task.subtasks.count))")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)

            // Subtask rows
            ForEach(task.subtasks) { sub in
                if editingSubtaskId == sub.id {
                    HStack(spacing: 8) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)

                        TextField("Subtask title...", text: $editingSubtaskTitle)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .focused($isSubtaskEditFocused)
                            .onSubmit {
                                saveSubtaskEdit(taskId: task.id, subtaskId: sub.id)
                            }
                            .onExitCommand {
                                cancelSubtaskEdit()
                            }

                        Button(action: {
                            saveSubtaskEdit(taskId: task.id, subtaskId: sub.id)
                        }) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)
                        .help("Save (Enter)")

                        Button(action: {
                            cancelSubtaskEdit()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Cancel (Esc)")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
                } else {
                    HStack(spacing: 8) {
                        Button(action: {
                            taskStore.toggleSubtask(in: task.id, subtaskId: sub.id)
                        }) {
                            Image(systemName: sub.isCompleted ? "checkmark.square.fill" : "square")
                                .font(.system(size: 14))
                                .foregroundStyle(sub.isCompleted ? Color.green : Color.secondary)
                        }
                        .buttonStyle(.plain)

                        Text(sub.title)
                            .font(.system(size: 12))
                            .strikethrough(sub.isCompleted)
                            .foregroundStyle(sub.isCompleted ? .secondary : .primary)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                startEditingSubtask(sub)
                            }

                        Spacer()

                        HStack(spacing: 6) {
                            Button(action: {
                                startEditingSubtask(sub)
                            }) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            .help("Edit Subtask")

                            Button(action: {
                                taskStore.deleteSubtask(in: task.id, subtaskId: sub.id)
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                            .help("Delete Subtask")
                        }
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button {
                            startEditingSubtask(sub)
                        } label: {
                            Label("Edit Subtask", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            taskStore.deleteSubtask(in: task.id, subtaskId: sub.id)
                        } label: {
                            Label("Delete Subtask", systemImage: "trash")
                        }
                    }
                }
            }

            // Add Subtask row
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                TextField("Add a subtask and press Enter...", text: $newSubtaskTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit {
                        submitSubtask(taskId: task.id)
                    }

                if !newSubtaskTitle.isEmpty {
                    Button("Add") {
                        submitSubtask(taskId: task.id)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func startEditingSubtask(_ sub: SubtaskItem) {
        editingSubtaskId = sub.id
        editingSubtaskTitle = sub.title
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isSubtaskEditFocused = true
        }
    }

    private func saveSubtaskEdit(taskId: UUID, subtaskId: UUID) {
        let trimmed = editingSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            taskStore.updateSubtask(in: taskId, subtaskId: subtaskId, newTitle: trimmed)
        }
        editingSubtaskId = nil
        editingSubtaskTitle = ""
        isSubtaskEditFocused = false
    }

    private func cancelSubtaskEdit() {
        editingSubtaskId = nil
        editingSubtaskTitle = ""
        isSubtaskEditFocused = false
    }

    private func submitSubtask(taskId: UUID) {
        taskStore.addSubtask(to: taskId, title: newSubtaskTitle)
        newSubtaskTitle = ""
    }
}
