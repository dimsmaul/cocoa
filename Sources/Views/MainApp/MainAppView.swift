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
                    HSplitView {
                        TaskListView(taskStore: taskStore, timerManager: timerManager)
                            .frame(minWidth: 340, idealWidth: 420)

                        TaskDetailView(
                            taskStore: taskStore,
                            timerManager: timerManager,
                            onLaunchNotchMode: onLaunchNotchMode,
                            onLaunchTowerMode: onLaunchTowerMode
                        )
                        .frame(minWidth: 320, idealWidth: 360)
                    }
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
}
