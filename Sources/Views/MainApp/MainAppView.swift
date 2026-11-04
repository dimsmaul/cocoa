import SwiftUI

public struct MainAppView: View {
    @Bindable var taskStore: TaskStore
    @Bindable var timerManager: TimerManager
    public var onLaunchNotchMode: () -> Void
    public var onLaunchTowerMode: () -> Void

    @State private var modalTask: TaskItem? = nil

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
        NavigationSplitView {
            SidebarView(taskStore: taskStore)
                .frame(minWidth: 200, idealWidth: 220)
        } detail: {
            VStack(spacing: 0) {
                // Main Content View (Full-width List or Kanban)
                Group {
                    if taskStore.viewMode == .list {
                        TaskListView(
                            taskStore: taskStore,
                            timerManager: timerManager,
                            onOpenDetail: { task in
                                modalTask = task
                            }
                        )
                    } else {
                        KanbanBoardView(
                            taskStore: taskStore,
                            timerManager: timerManager,
                            onOpenDetail: { task in
                                modalTask = task
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Persistent Music-Player-Style Focus Bar
                focusMusicPlayerBar
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                // View Mode Switcher: List vs Kanban Board (Left-aligned)
                Picker("View Mode", selection: $taskStore.viewMode) {
                    Image(systemName: "list.bullet").tag(TaskViewMode.list)
                    Image(systemName: "square.grid.3x2").tag(TaskViewMode.kanban)
                }
                .pickerStyle(.segmented)
                .help("Switch between List and Kanban Board view")

                Spacer()

                // Running Timer Indicator on the Trailing edge
                if timerManager.isRunning || timerManager.state == .paused {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(timerManager.isRunning ? Color.orange : Color.gray)
                            .frame(width: 8, height: 8)

                        Text(timerManager.formattedTime)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(timerManager.isRunning ? Color.orange : Color.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $modalTask) { task in
            TaskModalDialogView(
                task: task,
                taskStore: taskStore,
                timerManager: timerManager,
                onClose: {
                    modalTask = nil
                },
                onLaunchNotchMode: {
                    modalTask = nil
                    onLaunchNotchMode()
                },
                onLaunchTowerMode: {
                    modalTask = nil
                    onLaunchTowerMode()
                }
            )
            .preferredColorScheme(.dark)
        }
    }

    private var formattedElapsedTime: String {
        let elapsed = max(0, timerManager.totalSeconds - timerManager.remainingSeconds)
        let mins = elapsed / 60
        let secs = elapsed % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    // MARK: - Music Player Style Focus Bar
    private var focusMusicPlayerBar: some View {
        HStack(spacing: 14) {
            // LEFT: Active Track / Task Info
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(timerManager.isRunning ? Color.orange.opacity(0.18) : Color.primary.opacity(0.06))
                        .frame(width: 36, height: 36)

                    Image(systemName: timerManager.isRunning ? "waveform" : (timerManager.isBreak ? "cup.and.saucer.fill" : "target"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(timerManager.isRunning ? Color.orange : (timerManager.isBreak ? Color.green : Color.secondary))
                        .symbolEffect(.variableColor.iterative, isActive: timerManager.isRunning)
                }

                VStack(alignment: .leading, spacing: 2) {
                    if let activeTask = taskStore.activeTask {
                        Button(action: {
                            modalTask = activeTask
                        }) {
                            Text(activeTask.title)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                                .foregroundStyle(Color.primary)
                        }
                        .buttonStyle(.plain)
                        .help("Click to open task dialog")

                        HStack(spacing: 5) {
                            Text(activeTask.listName)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(taskStore.colorForList(activeTask.listName))

                            Text("•")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)

                            Text(timerManager.isRunning ? "Focusing" : (timerManager.state == .paused ? "Paused" : "Ready to focus"))
                                .font(.system(size: 10))
                                .foregroundStyle(timerManager.isRunning ? Color.orange : Color.secondary)
                        }
                    } else {
                        Text("No Task Active")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("Click a task to start focus")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: 220, alignment: .leading)
            }

            Spacer(minLength: 12)

            // CENTER: Music Player Line Scrubber & Playback Controls
            VStack(spacing: 4) {
                // Play / Pause / Reset / Complete buttons
                HStack(spacing: 12) {
                    Button(action: {
                        timerManager.reset()
                    }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Reset Focus Timer")

                    // Main Play/Pause Button
                    Button(action: {
                        timerManager.toggle()
                    }) {
                        ZStack {
                            Circle()
                                .fill(timerManager.isRunning ? Color.orange : Color.primary.opacity(0.12))
                                .frame(width: 30, height: 30)

                            Image(systemName: timerManager.isRunning ? "pause.fill" : "play.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(timerManager.isRunning ? Color.black : Color.primary)
                                .offset(x: timerManager.isRunning ? 0 : 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(timerManager.isRunning ? "Pause Focus" : "Start Focus")

                    Button(action: {
                        timerManager.completeCurrentSession()
                    }) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Complete Focus Session")
                }

                // Timeline Line (Elapsed ---●--- Total)
                HStack(spacing: 8) {
                    Text(formattedElapsedTime)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            // Background line
                            Capsule()
                                .fill(Color.primary.opacity(0.10))
                                .frame(height: 4)

                            // Animated orange gradient line
                            Capsule()
                                .fill(LinearGradient(
                                    colors: [Color.orange.opacity(0.85), Color.orange],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ))
                                .frame(width: max(4, geo.size.width * CGFloat(timerManager.progress)), height: 4)

                            // Scrubber knob
                            Circle()
                                .fill(Color.white)
                                .frame(width: 8, height: 8)
                                .shadow(color: .black.opacity(0.3), radius: 2)
                                .offset(x: max(0, min(geo.size.width - 8, geo.size.width * CGFloat(timerManager.progress) - 4)))
                        }
                        .frame(maxHeight: .infinity)
                    }
                    .frame(height: 12)

                    Text(timerManager.formattedTime)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(timerManager.isRunning ? Color.orange : Color.secondary)
                        .frame(width: 36, alignment: .leading)
                }
                .frame(maxWidth: 360)
            }

            Spacer(minLength: 12)

            // RIGHT: Island Notch & Tower Detach Shortcuts
            HStack(spacing: 6) {
                Button(action: onLaunchNotchMode) {
                    HStack(spacing: 4) {
                        Image(systemName: "menubar.arrow.up.rectangle")
                            .font(.system(size: 10))
                        Text("Notch Island")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.12))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Pop up into MacBook Notch Dynamic Island")

                Button(action: onLaunchTowerMode) {
                    HStack(spacing: 4) {
                        Image(systemName: "rectangle.inset.filled.and.cursorarrow")
                            .font(.system(size: 10))
                        Text("Tower")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.08))
                    .foregroundStyle(.primary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Float as Desktop Tower Card")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(
            Color(NSColor.windowBackgroundColor).opacity(0.95)
                .overlay(
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 1),
                    alignment: .top
                )
        )
    }
}
