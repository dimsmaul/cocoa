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
    @State private var newCommentText: String = ""
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
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "list.clipboard")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text("Task Details")
                        .font(.system(size: 13, weight: .bold))
                }

                Spacer()

                // Start Focus Button with Play Icon
                Button(action: {
                    if taskStore.activeTaskId != currentTask.id {
                        taskStore.selectTask(id: currentTask.id)
                        timerManager.syncWithActiveTask()
                        timerManager.start()
                    } else {
                        timerManager.toggle()
                    }
                }) {
                    let isCurrentRunning = timerManager.isRunning && taskStore.activeTaskId == currentTask.id
                    HStack(spacing: 5) {
                        Image(systemName: isCurrentRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(isCurrentRunning ? "Pause" : "Start")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4.5)
                    .background(isCurrentRunning ? Color.orange.opacity(0.2) : Color.orange)
                    .foregroundStyle(isCurrentRunning ? Color.orange : Color.black)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(timerManager.isRunning && taskStore.activeTaskId == currentTask.id ? "Pause Focus" : "Start Focus")

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
                    // Core Task Fields (Title, Notes, Board, Priority, List)
                    taskFieldsSection(task: currentTask)

                    Divider()

                    // Subtasks Checklist
                    subtasksSection(task: currentTask)

                    Divider()

                    // Comments & Activity
                    commentsSection(task: currentTask)
                }
                .padding(20)
            }
        }
        .frame(width: 560, height: 620)
        .background(.regularMaterial)
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
                        Button(action: {
                            taskStore.toggleSubtask(in: task.id, subtaskId: sub.id)
                        }) {
                            Image(systemName: sub.isCompleted ? "checkmark.square.fill" : "square")
                                .font(.system(size: 14))
                                .foregroundStyle(sub.isCompleted ? Color.green : Color.secondary)
                        }
                        .buttonStyle(.plain)

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
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Save (Enter)")

                        Button(action: {
                            cancelSubtaskEdit()
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        .help("Cancel (Esc)")
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 4)
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

    // MARK: - Comments Section
    private func commentsSection(task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.orange)
                Text("COMMENTS & ACTIVITY")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                Text("\(task.comments.count)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
            }

            if task.comments.isEmpty {
                Text("No comments yet. Leave a note or progress update below.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(task.comments) { comment in
                        HStack(alignment: .top, spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(Color.orange.opacity(0.18))
                                    .frame(width: 24, height: 24)
                                Text(String(comment.author.prefix(1)).uppercased())
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.orange)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(comment.author)
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(comment.formattedDate)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                    Spacer()
                                    Button(action: {
                                        taskStore.deleteComment(taskId: task.id, commentId: comment.id)
                                    }) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary.opacity(0.6))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Delete Comment")
                                }

                                Text(comment.content)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(8)
                        .background(Color.primary.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            // Comment input bar
            HStack(spacing: 8) {
                TextField("Add a comment and press Enter...", text: $newCommentText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit {
                        submitComment(taskId: task.id)
                    }

                if !newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("Post") {
                        submitComment(taskId: task.id)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func submitComment(taskId: UUID) {
        let trimmed = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        taskStore.addComment(to: taskId, author: "You", content: trimmed)
        newCommentText = ""
    }
}
