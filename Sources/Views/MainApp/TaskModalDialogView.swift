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
    @State private var clickMonitor: Any? = nil
    @State private var isShowingProjectPopover: Bool = false
    @State private var isShowingPriorityPopover: Bool = false
    @State private var isShowingEstimatePopover: Bool = false
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

    private var isCurrentTaskRunning: Bool {
        timerManager.isRunning && taskStore.activeTaskId == currentTask.id
    }

    private var isCurrentTaskStarted: Bool {
        let isCurrentActive = taskStore.activeTaskId == currentTask.id
        return currentTask.timeSpentSeconds > 0 || (isCurrentActive && timerManager.state != .idle)
    }

    private var currentTaskRemainingSeconds: Int {
        if taskStore.activeTaskId == currentTask.id && (timerManager.isRunning || timerManager.state == .paused) {
            return timerManager.remainingSeconds
        } else if currentTask.timeSpentSeconds > 0 {
            return max(0, currentTask.estimatedSeconds - currentTask.timeSpentSeconds)
        } else {
            return currentTask.estimatedSeconds
        }
    }

    private var formattedRemainingMinutes: String {
        let secs = currentTaskRemainingSeconds
        let mins = secs / 60
        if mins > 0 {
            return "\(mins)m"
        } else if secs > 0 {
            return "\(secs)s"
        } else {
            return "\(max(1, currentTask.estimatedMinutes))m"
        }
    }

    private var focusButtonText: String {
        if isCurrentTaskRunning {
            return "Pause"
        } else if isCurrentTaskStarted {
            return "Continue (\(formattedRemainingMinutes))"
        } else {
            return "Start"
        }
    }

    public var body: some View {
        // 2-Column Todoist Layout: Main Content (Left) + Attributes Sidebar (Right)
        HStack(spacing: 0) {
            // Left Column: Task Checkbox, Title, Description, Subtasks, Comments
            mainContentColumn(task: currentTask)

            Divider().opacity(0.12)

            // Right Column: Focus Button, Project, Date, Priority, Estimate
            metadataSidebar(task: currentTask)
        }
        .frame(width: 860, height: 640)
        .background(.regularMaterial)
        .background {
            // Keeps Esc closing the dialog now that there is no visible close button.
            Button("Close", action: onClose)
                .keyboardShortcut(.cancelAction)
                .opacity(0)
        }
        .onAppear(perform: setupOutsideClickMonitor)
        .onDisappear(perform: removeOutsideClickMonitor)
    }

    // MARK: - Focus Button: Start / Continue (Xm) / Pause
    private var focusButton: some View {
        Button(action: {
            if taskStore.activeTaskId != currentTask.id {
                taskStore.selectTask(id: currentTask.id)
                timerManager.reset()
                timerManager.syncWithActiveTask()
                timerManager.start()
            } else {
                timerManager.toggle()
            }
        }) {
            HStack(spacing: 5) {
                Image(systemName: isCurrentTaskRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .bold))
                Text(focusButtonText)
                    .font(.system(size: 12, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(isCurrentTaskRunning ? Color.orange.opacity(0.2) : Color.orange)
            .foregroundStyle(isCurrentTaskRunning ? Color.orange : Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isCurrentTaskRunning ? "Pause Focus" : (isCurrentTaskStarted ? "Continue Focus" : "Start Focus"))
    }

    // MARK: - Left Main Content Column (~68% width)
    private func mainContentColumn(task: TaskItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Task Checkbox + Title Row (Symmetrically aligned baseline)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Button(action: {
                        taskStore.toggleCompleted(id: task.id)
                        timerManager.syncWithActiveTask()
                    }) {
                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(task.isCompleted ? Color.green : Color.secondary)
                    }
                    .buttonStyle(.plain)

                    TextField("Task Title", text: Binding(
                        get: { task.title },
                        set: { newTitle in
                            taskStore.updateTask(id: task.id) { $0.title = newTitle }
                        }
                    ), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .semibold))
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
                        minHeight: 140,
                        growsWithContent: true
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
        VStack(alignment: .leading, spacing: 14) {
            focusButton

            // Project
            VStack(alignment: .leading, spacing: 4) {
                Text("Project")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                SidebarAttributeRow(
                    icon: "folder.fill",
                    iconColor: taskStore.colorForList(task.listName),
                    text: task.listName,
                    action: { isShowingProjectPopover.toggle() }
                )
                .popover(isPresented: $isShowingProjectPopover, arrowEdge: .bottom) {
                    ProjectPickerPopover(
                        lists: taskStore.lists,
                        selectedList: task.listName,
                        colorForList: { taskStore.colorForList($0) },
                        onSelect: { newList in
                            taskStore.updateTask(id: task.id) { $0.listName = newList }
                            isShowingProjectPopover = false
                        }
                    )
                }
            }

            Divider().opacity(0.10)

            // Date
            VStack(alignment: .leading, spacing: 4) {
                Text("Date")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                TaskDatePickerButton(task: task, taskStore: taskStore)
            }

            Divider().opacity(0.10)

            // Repeat
            VStack(alignment: .leading, spacing: 4) {
                Text("Repeat")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                TaskRecurrencePickerButton(task: task, taskStore: taskStore)
            }

            Divider().opacity(0.10)

            // Reminder
            VStack(alignment: .leading, spacing: 4) {
                Text("Reminder")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                TaskReminderPickerButton(task: task, taskStore: taskStore)
            }

            Divider().opacity(0.10)

            // Priority
            VStack(alignment: .leading, spacing: 4) {
                Text("Priority")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                SidebarAttributeRow(
                    icon: "flag.fill",
                    iconColor: priorityColor(task.priority),
                    text: task.priority.rawValue,
                    action: { isShowingPriorityPopover.toggle() }
                )
                .popover(isPresented: $isShowingPriorityPopover, arrowEdge: .bottom) {
                    PriorityPickerPopover(
                        selectedPriority: task.priority,
                        onSelect: { newP in
                            taskStore.updateTask(id: task.id) { $0.priority = newP }
                            isShowingPriorityPopover = false
                        }
                    )
                }
            }

            Divider().opacity(0.10)

            // Estimate
            VStack(alignment: .leading, spacing: 4) {
                Text("Estimate")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                SidebarAttributeRow(
                    icon: "timer",
                    iconColor: .secondary,
                    text: task.formattedEstimate,
                    action: { isShowingEstimatePopover.toggle() }
                )
                .popover(isPresented: $isShowingEstimatePopover, arrowEdge: .bottom) {
                    EstimatePickerPopover(
                        currentEstimate: task.estimatedMinutes,
                        onSelect: { mins in
                            updateEstimate(task: task, mins: mins)
                            isShowingEstimatePopover = false
                        }
                    )
                }
            }

            Spacer()
        }
        .frame(width: 220)
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
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
        taskStore.updateTask(id: task.id) { $0.estimatedMinutes = mins }
        if taskStore.activeTaskId == task.id {
            timerManager.syncWithActiveTask()
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
    private func setupOutsideClickMonitor() {
        removeOutsideClickMonitor()
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            // Outside means the window this sheet is attached to. Clicks in the dialog and
            // its popovers land on their own windows, so they can never close it.
            if event.window?.attachedSheet != nil {
                DispatchQueue.main.async {
                    onClose()
                }
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

// MARK: - Todoist-Style Minimal Sidebar Attribute Row
struct SidebarAttributeRow: View {
    let icon: String
    let iconColor: Color
    let text: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(iconColor)

                Text(text)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(isHovered ? Color.white.opacity(0.06) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Project Picker Popover
private struct ProjectPickerPopover: View {
    let lists: [String]
    let selectedList: String
    let colorForList: (String) -> Color
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("PROJECT")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .padding(.bottom, 2)

            ForEach(lists, id: \.self) { list in
                ProjectRow(
                    list: list,
                    isSelected: list == selectedList,
                    color: colorForList(list),
                    onSelect: { onSelect(list) }
                )
            }
        }
        .padding(6)
        .frame(minWidth: 160)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
    }
}

private struct ProjectRow: View {
    let list: String
    let isSelected: Bool
    let color: Color
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(color)

                Text(list)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isHovered ? Color.white.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Priority Picker Popover
private struct PriorityPickerPopover: View {
    let selectedPriority: TaskPriority
    let onSelect: (TaskPriority) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("PRIORITY")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .padding(.bottom, 2)

            ForEach(TaskPriority.allCases, id: \.self) { p in
                PriorityRow(
                    priority: p,
                    isSelected: p == selectedPriority,
                    onSelect: { onSelect(p) }
                )
            }
        }
        .padding(6)
        .frame(minWidth: 140)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
    }
}

private struct PriorityRow: View {
    let priority: TaskPriority
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isHovered = false

    private var priorityColor: Color {
        switch priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        }
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(priorityColor)

                Text(priority.rawValue)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isHovered ? Color.white.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Estimate Picker Popover
private struct EstimatePickerPopover: View {
    let currentEstimate: Int
    let onSelect: (Int) -> Void

    let presets = [15, 25, 45, 60, 90]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("ESTIMATE")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .padding(.bottom, 2)

            ForEach(presets, id: \.self) { mins in
                EstimateRow(
                    minutes: mins,
                    isSelected: currentEstimate == mins,
                    onSelect: { onSelect(mins) }
                )
            }
        }
        .padding(6)
        .frame(minWidth: 150)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
    }
}

private struct EstimateRow: View {
    let minutes: Int
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isHovered = false

    private var label: String {
        if minutes == 25 {
            return "25m (Pomodoro)"
        }
        return "\(minutes)m"
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: "timer")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isHovered ? Color.white.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
