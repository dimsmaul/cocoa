import SwiftUI

public struct TaskDetailView: View {
    @Bindable var taskStore: TaskStore
    @Bindable var timerManager: TimerManager
    public var onLaunchNotchMode: () -> Void
    public var onLaunchTowerMode: () -> Void

    @State private var newSubtaskTitle: String = ""
    @State private var isBreakingDownWithAI: Bool = false
    @State private var aiErrorMessage: String? = nil

    public init(
        taskStore: TaskStore,
        timerManager: TimerManager,
        onLaunchNotchMode: @escaping () -> Void,
        onLaunchTowerMode: @escaping () -> Void
    ) {
        self.taskStore = taskStore
        self.timerManager = timerManager
        self.onLaunchNotchMode = onLaunchNotchMode
        self.onLaunchTowerMode = onLaunchTowerMode
    }

    public var body: some View {
        if let task = taskStore.selectedTask {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Focus Session Card
                    focusSessionCard(task: task)

                    // Task Core Fields
                    taskFieldsSection(task: task)

                    Divider()

                    // Subtasks Checklist
                    subtasksSection(task: task)
                }
                .padding(20)
            }
        } else {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 32))
                    .foregroundStyle(.tertiary)
                Text("Select a task to view details")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    // MARK: - Focus Session Card
    private func focusSessionCard(task: TaskItem) -> some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("FOCUS TIMER")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(timerManager.isRunning ? "Session in Progress" : (timerManager.state == .paused ? "Session Paused" : "Ready to Focus"))
                        .font(.system(size: 12, weight: .semibold))
                }

                Spacer()

                // Mode switch pills
                HStack(spacing: 6) {
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
                        ringColor: timerManager.isRunning ? .orange : .secondary
                    )
                    .frame(width: 90, height: 90)

                    VStack(spacing: 2) {
                        Text(timerManager.formattedTime)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundStyle(timerManager.isRunning ? Color.orange : Color.primary)
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
                            Image(systemName: timerManager.isRunning && taskStore.activeTaskId == task.id ? "pause.fill" : "play.fill")
                                .font(.system(size: 13, weight: .bold))
                            Text(timerManager.isRunning && taskStore.activeTaskId == task.id ? "Pause Focus" : "Start Focus")
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
                        }
                        .buttonStyle(.plain)

                        Button(action: { timerManager.completeCurrentSession() }) {
                            Text("Mark Done")
                                .font(.system(size: 11, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(Color.green.opacity(0.15))
                                .foregroundStyle(.green)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
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
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
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
                            if let index = taskStore.tasks.firstIndex(where: { $0.id == task.id }) {
                                taskStore.tasks[index].notes = newNotes
                            }
                        }
                    ),
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
                    TaskDatePickerButton(task: task, taskStore: taskStore, width: 122)
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
                    .frame(width: 130)
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
                    .frame(width: 130)
                }
            }
        }
    }

    // MARK: - Subtasks Section
    private func subtasksSection(task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SUBTASKS (\(task.subtasks.filter { $0.isCompleted }.count)/\(task.subtasks.count))")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: {
                    triggerAIBreakdown(task: task)
                }) {
                    HStack(spacing: 4) {
                        if isBreakingDownWithAI {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        Text(isBreakingDownWithAI ? "Analyzing..." : "AI Breakdown")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.purple.opacity(0.15))
                    .foregroundStyle(Color.purple)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isBreakingDownWithAI)
                .help("Use AI to automatically break down this task into subtasks")
            }

            if let aiErr = aiErrorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                    Text(aiErr)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Dismiss") {
                        aiErrorMessage = nil
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(6)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Subtask rows
            ForEach(task.subtasks) { sub in
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

                    Spacer()

                    Button(action: {
                        taskStore.deleteSubtask(in: task.id, subtaskId: sub.id)
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 3)
            }

            // Add Subtask row
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                TextField("Add a subtask...", text: $newSubtaskTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit {
                        submitSubtask(taskId: task.id)
                    }

                if !newSubtaskTitle.isEmpty {
                    Button("Add") {
                        submitSubtask(taskId: task.id)
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func submitSubtask(taskId: UUID) {
        taskStore.addSubtask(to: taskId, title: newSubtaskTitle)
        newSubtaskTitle = ""
    }

    private func triggerAIBreakdown(task: TaskItem) {
        guard !isBreakingDownWithAI else { return }
        aiErrorMessage = nil
        isBreakingDownWithAI = true

        Task {
            do {
                let subtasks = try await AIService.shared.breakdownTask(title: task.title, notes: task.notes)
                await MainActor.run {
                    for sub in subtasks {
                        taskStore.addSubtask(to: task.id, title: sub)
                    }
                    self.isBreakingDownWithAI = false
                }
            } catch {
                await MainActor.run {
                    self.aiErrorMessage = error.localizedDescription
                    self.isBreakingDownWithAI = false
                }
            }
        }
    }
}
