import SwiftUI

public struct FloatingTowerView: View {
    @Bindable var taskStore: TaskStore
    @Bindable var timerManager: TimerManager
    public var onDockToNotch: () -> Void
    public var onOpenMainApp: () -> Void

    @State private var newTaskTitle: String = ""
    @State private var newEstimatedMinutes: Int = 25
    @State private var selectedTab: TaskBoard = .today
    @State private var isSubtasksExpanded: Bool = true
    @State private var showNotesInline: Bool = false
    @State private var newSubtaskTitle: String = ""
    @State private var editingSubtaskId: UUID? = nil
    @State private var editingSubtaskTitle: String = ""
    @FocusState private var isSubtaskEditFocused: Bool
    @State private var showDetailModal: Bool = false

    public init(
        taskStore: TaskStore,
        timerManager: TimerManager,
        onDockToNotch: @escaping () -> Void,
        onOpenMainApp: @escaping () -> Void
    ) {
        self.taskStore = taskStore
        self.timerManager = timerManager
        self.onDockToNotch = onDockToNotch
        self.onOpenMainApp = onOpenMainApp
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header bar
            headerBar

            Divider()
                .opacity(0.15)

            // Active Task Hero Card
            activeHeroCard
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider()
                .opacity(0.15)

            // Task list section
            taskListSection

            Divider()
                .opacity(0.15)

            // Bottom Add Task Bar
            quickAddBar
                .padding(12)
        }
        .frame(width: 330, height: 560)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .sheet(isPresented: $showDetailModal) {
            if let active = taskStore.activeTask {
                TaskModalDialogView(
                    task: active,
                    taskStore: taskStore,
                    timerManager: timerManager,
                    onClose: { showDetailModal = false },
                    onLaunchNotchMode: {
                        showDetailModal = false
                        onDockToNotch()
                    },
                    onLaunchTowerMode: {
                        showDetailModal = false
                    }
                )
            }
        }
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        HStack(spacing: 8) {
            if let logoImage = NSImage(contentsOf: Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/CocoaLogo.png")) {
                Image(nsImage: logoImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Text("🍫")
                    .font(.system(size: 16))
            }

            Text("Cocoa")
                .font(.system(size: 14, weight: .bold))

            Spacer()

            // Open Main App button
            Button(action: onOpenMainApp) {
                Image(systemName: "macwindow")
                    .font(.system(size: 11))
                    .padding(5)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Open Main App Dashboard")

            // Dock to Notch button
            Button(action: onDockToNotch) {
                HStack(spacing: 4) {
                    Image(systemName: "menubar.arrow.up.rectangle")
                        .font(.system(size: 11))
                    Text("Dock to Notch")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.15))
                .foregroundStyle(.orange)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Attach Cocoa as a Dynamic Island pill at the Mac notch")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Active Hero Card
    private var activeHeroCard: some View {
        VStack(spacing: 12) {
            if let active = taskStore.activeTask {
                VStack(spacing: 5) {
                    HStack(spacing: 6) {
                        Text("CURRENT FOCUS")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)

                        listBadge(for: active.listName)
                    }

                    Text(active.title)
                        .font(.system(size: 15, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                HStack(spacing: 20) {
                    // Circular Progress & Big Timer
                    ZStack {
                        ProgressRing(
                            progress: timerManager.progress,
                            lineWidth: 5,
                            ringColor: timerManager.isRunning ? .orange : .secondary
                        )
                        .frame(width: 80, height: 80)

                        VStack(spacing: 1) {
                            Text(timerManager.formattedTime)
                                .font(.system(size: 18, weight: .bold, design: .monospaced))
                                .foregroundStyle(timerManager.isRunning ? Color.orange : Color.primary)

                            Text(timerManager.isRunning ? "RUNNING" : (timerManager.state == .paused ? "PAUSED" : "READY"))
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Controls
                    VStack(alignment: .leading, spacing: 8) {
                        Button(action: {
                            timerManager.toggle()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: timerManager.isRunning ? "pause.fill" : "play.fill")
                                    .font(.system(size: 12, weight: .bold))
                                Text(timerManager.isRunning ? "Pause" : "Start Focus")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(timerManager.isRunning ? Color.orange.opacity(0.2) : Color.orange)
                            .foregroundStyle(timerManager.isRunning ? Color.orange : Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)

                        HStack(spacing: 6) {
                            Button(action: {
                                timerManager.reset()
                            }) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 11))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background(Color.secondary.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .help("Reset Timer")

                            Button(action: {
                                timerManager.completeCurrentSession()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                    Text("Done")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(Color.green.opacity(0.15))
                                .foregroundStyle(.green)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .help("Mark Complete")
                        }
                    }
                }

                // Subtasks & Details Bar
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Button(action: {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                isSubtasksExpanded.toggle()
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: isSubtasksExpanded ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 8, weight: .bold))
                                let done = active.subtasks.filter(\.isCompleted).count
                                Text("Subtasks (\(done)/\(active.subtasks.count))")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        // Toggle Notes button
                        Button(action: {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                showNotesInline.toggle()
                            }
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: showNotesInline ? "note.text.badge.plus" : "note.text")
                                    .font(.system(size: 10))
                                Text("Notes")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(showNotesInline ? Color.orange.opacity(0.18) : Color.primary.opacity(0.06))
                            .foregroundStyle(showNotesInline ? Color.orange : Color.secondary)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        // Open Full Modal Sheet
                        Button(action: { showDetailModal = true }) {
                            Image(systemName: "pencil.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Edit Full Details & Subtasks")
                    }

                    // Notes Inline Box (Native Rich Text via RichTextKit)
                    if showNotesInline {
                        NativeRichTextEditor(
                            text: Binding(
                                get: { active.notes },
                                set: { newNotes in
                                    taskStore.updateNotes(for: active.id, notes: newNotes)
                                }
                            ),
                            taskId: active.id,
                            baseFontSize: 13.5,
                            minHeight: 85
                        )
                    }

                    // Subtasks List
                    if isSubtasksExpanded {
                        VStack(spacing: 4) {
                            if active.subtasks.isEmpty {
                                Text("No subtasks yet. Add a checkpoint below.")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.tertiary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 2)
                            } else {
                                ForEach(active.subtasks) { subtask in
                                    if editingSubtaskId == subtask.id {
                                        HStack(spacing: 4) {
                                            Image(systemName: "pencil")
                                                .font(.system(size: 9))
                                                .foregroundStyle(.orange)

                                            TextField("Edit subtask...", text: $editingSubtaskTitle)
                                                .textFieldStyle(.plain)
                                                .font(.system(size: 11))
                                                .focused($isSubtaskEditFocused)
                                                .onSubmit {
                                                    let trimmed = editingSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                                                    if !trimmed.isEmpty {
                                                        taskStore.updateSubtask(in: active.id, subtaskId: subtask.id, newTitle: trimmed)
                                                    }
                                                    editingSubtaskId = nil
                                                    editingSubtaskTitle = ""
                                                    isSubtaskEditFocused = false
                                                }
                                                .onExitCommand {
                                                    editingSubtaskId = nil
                                                    editingSubtaskTitle = ""
                                                    isSubtaskEditFocused = false
                                                }

                                            Button(action: {
                                                let trimmed = editingSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                                                if !trimmed.isEmpty {
                                                    taskStore.updateSubtask(in: active.id, subtaskId: subtask.id, newTitle: trimmed)
                                                }
                                                editingSubtaskId = nil
                                                editingSubtaskTitle = ""
                                                isSubtaskEditFocused = false
                                            }) {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(.green)
                                            }
                                            .buttonStyle(.plain)

                                            Button(action: {
                                                editingSubtaskId = nil
                                                editingSubtaskTitle = ""
                                                isSubtaskEditFocused = false
                                            }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(.secondary)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                    } else {
                                        HStack(spacing: 6) {
                                            Button(action: {
                                                taskStore.toggleSubtask(in: active.id, subtaskId: subtask.id)
                                            }) {
                                                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(subtask.isCompleted ? Color.green : Color.secondary)
                                            }
                                            .buttonStyle(.plain)

                                            Text(subtask.title)
                                                .font(.system(size: 11))
                                                .strikethrough(subtask.isCompleted)
                                                .foregroundStyle(subtask.isCompleted ? .secondary : .primary)
                                                .lineLimit(1)
                                                .contentShape(Rectangle())
                                                .onTapGesture(count: 2) {
                                                    editingSubtaskId = subtask.id
                                                    editingSubtaskTitle = subtask.title
                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                                        isSubtaskEditFocused = true
                                                    }
                                                }

                                            Spacer()

                                            HStack(spacing: 4) {
                                                Button(action: {
                                                    editingSubtaskId = subtask.id
                                                    editingSubtaskTitle = subtask.title
                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                                        isSubtaskEditFocused = true
                                                    }
                                                }) {
                                                    Image(systemName: "pencil")
                                                        .font(.system(size: 9))
                                                        .foregroundStyle(.secondary.opacity(0.7))
                                                }
                                                .buttonStyle(.plain)
                                                .help("Edit Subtask")

                                                Button(action: {
                                                    taskStore.deleteSubtask(in: active.id, subtaskId: subtask.id)
                                                }) {
                                                    Image(systemName: "xmark")
                                                        .font(.system(size: 8))
                                                        .foregroundStyle(.tertiary)
                                                }
                                                .buttonStyle(.plain)
                                                .help("Delete Subtask")
                                            }
                                        }
                                        .padding(.vertical, 1)
                                        .contentShape(Rectangle())
                                        .contextMenu {
                                            Button {
                                                editingSubtaskId = subtask.id
                                                editingSubtaskTitle = subtask.title
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                                    isSubtaskEditFocused = true
                                                }
                                            } label: {
                                                Label("Edit Subtask", systemImage: "pencil")
                                            }

                                            Button(role: .destructive) {
                                                taskStore.deleteSubtask(in: active.id, subtaskId: subtask.id)
                                            } label: {
                                                Label("Delete Subtask", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                            }

                            // Add subtask inline input
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)

                                TextField("Add subtask...", text: $newSubtaskTitle)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 11))
                                    .onSubmit {
                                        let trimmed = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                                        if !trimmed.isEmpty {
                                            taskStore.addSubtask(to: active.id, title: trimmed)
                                            newSubtaskTitle = ""
                                        }
                                    }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .padding(.top, 4)
            } else {
                VStack(spacing: 6) {
                    Text("No Active Task Selected")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Select a task below or create a new one to start.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    // MARK: - Task List Section
    private var taskListSection: some View {
        VStack(spacing: 6) {
            // Tab Selector - Modern consistent capsule pills
            HStack(spacing: 6) {
                tabButton(title: "Today (\(taskStore.todayTasks.count))", board: .today)
                tabButton(title: "Done (\(taskStore.completedTasks.count))", board: .done)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            // Scrollable List
            ScrollView {
                LazyVStack(spacing: 4) {
                    let list = selectedTab == .today ? taskStore.todayTasks : taskStore.completedTasks

                    if list.isEmpty {
                        VStack(spacing: 4) {
                            Text(selectedTab == .today ? "No tasks for today 🎉" : "No completed tasks yet")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 24)
                    } else {
                        ForEach(list) { task in
                            TaskRowView(
                                task: task,
                                isSelected: task.id == taskStore.activeTaskId,
                                listColor: taskStore.colorForList(task.listName),
                                onSelect: {
                                    taskStore.selectTask(id: task.id)
                                    timerManager.syncWithActiveTask()
                                },
                                onToggle: {
                                    taskStore.toggleCompleted(id: task.id)
                                    timerManager.syncWithActiveTask()
                                },
                                onDelete: {
                                    taskStore.deleteTask(id: task.id)
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }

    private func tabButton(title: String, board: TaskBoard) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                selectedTab = board
            }
        }) {
            Text(title)
                .font(.system(size: 11, weight: selectedTab == board ? .bold : .medium))
                .foregroundStyle(selectedTab == board ? .white : .white.opacity(0.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(selectedTab == board ? Color.white.opacity(0.16) : Color.white.opacity(0.04))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(selectedTab == board ? Color.white.opacity(0.18) : Color.clear, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Quick Add Bar
    private var quickAddBar: some View {
        HStack(spacing: 8) {
            TextField("Add task, press Enter...", text: $newTaskTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onSubmit {
                    submitTask()
                }

            // Estimate Picker (e.g. 25m)
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
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button(action: submitTask) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.orange)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private func submitTask() {
        guard !newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        taskStore.addTask(title: newTaskTitle, estimatedMinutes: newEstimatedMinutes)
        newTaskTitle = ""
        timerManager.syncWithActiveTask()
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
        .padding(.vertical, 1.5)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}
