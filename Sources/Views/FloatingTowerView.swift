import SwiftUI

private struct SubtasksHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

enum FocusCarousel {
    /// True when the new task sits at or below the old one in the list, so it enters from the right.
    static func slidesForward(from old: UUID?, to new: UUID?, in order: [UUID]) -> Bool {
        guard let old, let new,
              let oldIndex = order.firstIndex(of: old),
              let newIndex = order.firstIndex(of: new) else { return true }
        return newIndex >= oldIndex
    }
}

/// Stays put while the task below it slides, because these controls are always in use.
struct TowerTimerControls: View {
    let time: String
    let status: String
    let isRunning: Bool
    let taskId: UUID?
    let onToggle: () -> Void
    let onReset: () -> Void
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .leading) {
                    Text(time)
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                        .foregroundStyle(isRunning ? Color.orange : Color.primary)
                        .id(taskId)
                        .transition(.opacity)
                }

                Text(status)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            iconButton(
                icon: isRunning ? "pause.fill" : "play.fill",
                label: isRunning ? "Pause" : "Start Focus",
                foreground: isRunning ? .orange : .black,
                background: isRunning ? Color.orange.opacity(0.2) : .orange,
                action: onToggle
            )
            iconButton(
                icon: "arrow.counterclockwise",
                label: "Reset Timer",
                foreground: .primary,
                background: Color.secondary.opacity(0.15),
                action: onReset
            )
            iconButton(
                icon: "checkmark",
                label: "Mark Complete",
                foreground: .green,
                background: Color.green.opacity(0.15),
                action: onDone
            )
        }
    }

    private func iconButton(
        icon: String,
        label: String,
        foreground: Color,
        background: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(foreground)
                .frame(width: 32, height: 32)
                .background(background)
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

public struct FloatingTowerView: View {
    public static let height: CGFloat = 680
    /// About six rows. Past this the subtasks scroll, so the task list below keeps its space.
    private static let subtasksMaxHeight: CGFloat = 132
    private static let subtasksEndID = "subtasksEnd"

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
    @State private var subtasksContentHeight: CGFloat = 0
    @State private var displayedTaskId: UUID? = nil
    @State private var slidesForward: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .onAppear {
            displayedTaskId = taskStore.activeTask?.id
        }
        .onChange(of: taskStore.activeTask?.id) { oldId, newId in
            slidesForward = FocusCarousel.slidesForward(from: oldId, to: newId, in: taskStore.tasks.map(\.id))
            // A leaving view keeps the transition it last rendered with, so the new
            // direction has to render once before the task changes.
            DispatchQueue.main.async {
                withAnimation(focusAnimation) {
                    displayedTaskId = newId
                }
            }
        }
        .frame(width: 330, height: Self.height)
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
        VStack(spacing: 10) {
            if taskStore.activeTask != nil {
                TowerTimerControls(
                    time: timerManager.formattedTime,
                    status: timerManager.isRunning ? "RUNNING" : (timerManager.state == .paused ? "PAUSED" : "READY"),
                    isRunning: timerManager.isRunning,
                    taskId: displayedTaskId,
                    onToggle: { timerManager.toggle() },
                    onReset: { timerManager.reset() },
                    onDone: { timerManager.completeCurrentSession() }
                )
            }

            // ZStack so the old and new task overlap during the slide instead of stacking and doubling the height.
            ZStack(alignment: .top) {
                heroContent
                    .id(displayedTask?.id)
                    .transition(focusTransition)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var focusAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.86)
    }

    private var focusTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: slidesForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: slidesForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    /// The task on screen, which follows the active task once its slide begins.
    private var displayedTask: TaskItem? {
        taskStore.tasks.first { $0.id == displayedTaskId } ?? taskStore.activeTask
    }

    private var heroContent: some View {
        VStack(spacing: 12) {
            if let active = displayedTask {
                VStack(spacing: 5) {
                    Text("CURRENT FOCUS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)

                    Text(active.title)
                        .font(.system(size: 15, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
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

                    // Notes Inline Box
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
                                ScrollViewReader { proxy in
                                ScrollView {
                                VStack(spacing: 4) {
                                ForEach(active.subtasks) { subtask in
                                    if editingSubtaskId == subtask.id {
                                        HStack(spacing: 6) {
                                            Button(action: {
                                                taskStore.toggleSubtask(in: active.id, subtaskId: subtask.id)
                                            }) {
                                                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(subtask.isCompleted ? Color.green : Color.secondary)
                                            }
                                            .buttonStyle(.plain)

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
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundStyle(.secondary)
                                            }
                                            .buttonStyle(.plain)

                                            Button(action: {
                                                editingSubtaskId = nil
                                                editingSubtaskTitle = ""
                                                isSubtaskEditFocused = false
                                            }) {
                                                Image(systemName: "xmark")
                                                    .font(.system(size: 8))
                                                    .foregroundStyle(.tertiary)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.vertical, 1)
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

                                Color.clear
                                    .frame(height: 0)
                                    .id(Self.subtasksEndID)
                                }
                                .background(GeometryReader { geometry in
                                    Color.clear.preference(key: SubtasksHeightKey.self, value: geometry.size.height)
                                })
                                }
                                .frame(height: min(subtasksContentHeight, Self.subtasksMaxHeight))
                                .onPreferenceChange(SubtasksHeightKey.self) { subtasksContentHeight = $0 }
                                .onChange(of: active.subtasks.count) { oldCount, newCount in
                                    guard newCount > oldCount else { return }
                                    // Waits a pass so the new row exists before scrolling to it.
                                    DispatchQueue.main.async {
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            proxy.scrollTo(Self.subtasksEndID, anchor: .bottom)
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
    }

    // MARK: - Task List Section
    private var taskListSection: some View {
        VStack(spacing: 6) {
            // Tab Selector - Modern consistent capsule pills
            HStack(spacing: 6) {
                tabButton(title: "Today (\(taskStore.todayGroupTasks.count))", board: .today)
                tabButton(title: "Done (\(taskStore.completedTasks.count))", board: .done)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            // Scrollable List
            ScrollView {
                LazyVStack(spacing: 4) {
                    let list = selectedTab == .today ? taskStore.todayGroupTasks : taskStore.completedTasks

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
}
