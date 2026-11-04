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

                // Top Right Section: [Timer (when started)] [Notch Island] [Tower]
                HStack(spacing: 8) {
                    // Pas di start, di sebelah kiri Notch Island & Tower ada timer
                    if timerManager.isRunning || timerManager.state == .paused {
                        HStack(spacing: 6) {
                            Button(action: {
                                timerManager.toggle()
                            }) {
                                Image(systemName: timerManager.isRunning ? "pause.fill" : "play.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(timerManager.isRunning ? Color.orange : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(timerManager.isRunning ? "Pause Focus" : "Resume Focus")

                            Text(timerManager.formattedTime)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(timerManager.isRunning ? Color.orange : Color.secondary)

                            Button(action: {
                                timerManager.reset()
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                            .help("Reset Focus Timer")
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Capsule())
                    }

                    // Notch Island button
                    Button(action: onLaunchNotchMode) {
                        HStack(spacing: 4) {
                            Image(systemName: "menubar.arrow.up.rectangle")
                                .font(.system(size: 11))
                            Text("Notch Island")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.12))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Minimize to MacBook Notch Dynamic Island")

                    // Tower button
                    Button(action: onLaunchTowerMode) {
                        HStack(spacing: 4) {
                            Image(systemName: "rectangle.inset.filled.and.cursorarrow")
                                .font(.system(size: 11))
                            Text("Tower")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.08))
                        .foregroundStyle(.primary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Pop out as Floating Desktop Tower")
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
}
