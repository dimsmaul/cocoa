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
    @State private var sheetWindow: NSWindow? = nil
    @State private var clickMonitor: Any? = nil
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
            // Header Bar
            headerBar

            Divider().opacity(0.12)

            // 2-Column Todoist Layout: Main Content (Left) + Attributes Sidebar (Right)
            HStack(spacing: 0) {
                // Left Column: Task Checkbox, Title, Description, Subtasks, Comments
                mainContentColumn(task: currentTask)

                Divider().opacity(0.12)

                // Right Column: Project, Date, Priority, Estimate, Board, Delete
                metadataSidebar(task: currentTask)
            }
        }
        .frame(width: 720, height: 560)
        .background(.regularMaterial)
        .background(WindowAccessor { window in
            self.sheetWindow = window
            setupOutsideClickMonitor(for: window)
        })
        .onDisappear {
            removeOutsideClickMonitor()
        }
    }

    // MARK: - Header Bar (Todoist style: Project breadcrumb on left, Start + Close on right)
    private var headerBar: some View {
        HStack(spacing: 10) {
            // Project/List Breadcrumb
            HStack(spacing: 6) {
                Image(systemName: "tray.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(taskStore.colorForList(currentTask.listName))
                Text(currentTask.listName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
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

            // Close Button
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
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: - Left Main Content Column (~68% width)
    private func mainContentColumn(task: TaskItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Task Checkbox + Title Row
                HStack(alignment: .top, spacing: 12) {
                    Button(action: {
                        taskStore.toggleCompleted(id: task.id)
                        timerManager.syncWithActiveTask()
                    }) {
                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(task.isCompleted ? Color.green : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)

                    TextField("Task Title", text: Binding(
                        get: { task.title },
                        set: { newTitle in
                            if let index = taskStore.tasks.firstIndex(where: { $0.id == task.id }) {
                                taskStore.tasks[index].title = newTitle
                            }
                        }
                    ), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1...5)
                }

                // Description / Notes (Rich Text)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("Description")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    NativeRichTextEditor(
                        text: Binding(
                            get: { task.notes },
                            set: { newNotes in
                                taskStore.updateNotes(for: task.id, notes: newNotes)
                            }
                        ),
                        taskId: task.id,
                        baseFontSize: 13,
                        minHeight: 90
                    )
                }

                Divider().opacity(0.12)

                // Subtasks Section
                subtasksSection(task: task)

                Divider().opacity(0.12)

                // Comments Section
                commentsSection(task: task)
            }
            .padding(18)
        }
    }

    // MARK: - Right Attributes Sidebar (~32% width)
    private func metadataSidebar(task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Project / List
            VStack(alignment: .leading, spacing: 4) {
                Text("Project")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)

                Menu {
                    ForEach(taskStore.lists, id: \.self) { list in
                        Button(action: {
                            if let idx = taskStore.tasks.firstIndex(where: { $0.id == task.id }) {
                                taskStore.tasks[idx].listName = list
                            }
                        }) {
                            HStack {
                                Text(list)
                                if task.listName == list {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(taskStore.colorForList(task.listName))
                        Text(task.listName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }

            Divider().opacity(0.10)

            // Date
            VStack(alignment: .leading, spacing: 4) {
                Text("Date")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)

                TaskDatePickerButton(task: task, taskStore: taskStore, width: 175)
            }

            Divider().opacity(0.10)

            // Priority
            VStack(alignment: .leading, spacing: 4) {
                Text("Priority")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)

                Menu {
                    ForEach(TaskPriority.allCases, id: \.self) { p in
                        Button(action: {
                            if let idx = taskStore.tasks.firstIndex(where: { $0.id == task.id }) {
                                taskStore.tasks[idx].priority = p
                            }
                        }) {
                            HStack {
                                Text(p.rawValue)
                                if task.priority == p {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(priorityColor(task.priority))
                        Text(task.priority.rawValue)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }

            Divider().opacity(0.10)

            // Estimate
            VStack(alignment: .leading, spacing: 4) {
                Text("Estimate")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)

                Menu {
                    Button("15 mins") { updateEstimate(task: task, mins: 15) }
                    Button("25 mins (Pomodoro)") { updateEstimate(task: task, mins: 25) }
                    Button("45 mins") { updateEstimate(task: task, mins: 45) }
                    Button("60 mins") { updateEstimate(task: task, mins: 60) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "timer")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(task.formattedEstimate)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }

            Divider().opacity(0.10)

            // Board
            VStack(alignment: .leading, spacing: 4) {
                Text("Board")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)

                Menu {
                    ForEach(TaskBoard.allCases, id: \.self) { b in
                        Button(action: {
                            taskStore.moveTask(id: task.id, to: b)
                        }) {
                            HStack {
                                Text(b.rawValue)
                                if task.board == b {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: task.board.iconName)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.orange)
                        Text(task.board.rawValue)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Divider().opacity(0.10)

            // Delete Task
            Button(role: .destructive, action: {
                taskStore.deleteTask(id: task.id)
                timerManager.syncWithActiveTask()
                onClose()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                    Text("Delete Task")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Color.red.opacity(0.85))
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 200)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(Color.primary.opacity(0.02))
    }

    // MARK: - Subtasks Section
    private func subtasksSection(task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Sub-tasks")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                if !task.subtasks.isEmpty {
                    Text("\(task.subtasks.filter { $0.isCompleted }.count)/\(task.subtasks.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Capsule())
                }
            }

            // Subtask rows
            ForEach(task.subtasks) { sub in
                if editingSubtaskId == sub.id {
                    HStack(spacing: 8) {
                        Button(action: {
                            taskStore.toggleSubtask(in: task.id, subtaskId: sub.id)
                        }) {
                            Image(systemName: sub.isCompleted ? "checkmark.circle.fill" : "circle")
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
                            Image(systemName: sub.isCompleted ? "checkmark.circle.fill" : "circle")
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

            // Todoist style "+ Add sub-task" row
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.orange)

                TextField("Add sub-task...", text: $newSubtaskTitle)
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
            .background(Color.primary.opacity(0.03))
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
                Text("Comments")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                if !task.comments.isEmpty {
                    Text("\(task.comments.count)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Capsule())
                }
            }

            if !task.comments.isEmpty {
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

            // Comment input bar (Todoist capsule pill style)
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.2))
                        .frame(width: 22, height: 22)
                    Text("D")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.orange)
                }

                TextField("Comment", text: $newCommentText)
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
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04))
            .clipShape(Capsule())
        }
    }

    private func submitComment(taskId: UUID) {
        let trimmed = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        taskStore.addComment(to: taskId, author: "You", content: trimmed)
        newCommentText = ""
    }

    private func updateEstimate(task: TaskItem, mins: Int) {
        if let index = taskStore.tasks.firstIndex(where: { $0.id == task.id }) {
            taskStore.tasks[index].estimatedMinutes = mins
            if taskStore.activeTaskId == task.id {
                timerManager.syncWithActiveTask()
            }
        }
    }

    private func priorityColor(_ priority: TaskPriority) -> Color {
        switch priority {
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }

    // MARK: - Native Sheet Outside Click Dismissal
    private func setupOutsideClickMonitor(for window: NSWindow) {
        removeOutsideClickMonitor()
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak window] event in
            guard let window else { return event }
            let clickScreenLocation = NSEvent.mouseLocation
            if !window.frame.contains(clickScreenLocation) {
                DispatchQueue.main.async {
                    onClose()
                }
                return nil
            }
            return event
        }
    }

    private func removeOutsideClickMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }
}

// MARK: - Native Window Accessor Helper
private struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onWindow(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
