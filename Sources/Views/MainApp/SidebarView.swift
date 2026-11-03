import SwiftUI

public struct SidebarView: View {
    @Bindable var taskStore: TaskStore
    @State private var isShowingNewListSheet = false

    public init(taskStore: TaskStore) {
        self.taskStore = taskStore
    }

    public var body: some View {
        VStack(spacing: 0) {
            List(selection: $taskStore.selectedSection) {
                // Section: Smart Boards
                Section("Boards") {
                    ForEach(TaskBoard.allCases, id: \.self) { board in
                        NavigationLink(value: SidebarSection.board(board)) {
                            Label {
                                Text(board.rawValue)
                                    .font(.system(size: 13, weight: .medium))
                            } icon: {
                                Image(systemName: board.iconName)
                                    .foregroundStyle(boardColor(for: board))
                            }
                            .badge(taskStore.countForBoard(board))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                    }
                }
                .collapsible(false)

                // Section: Custom Lists with User-Selected Folder Colors
                Section {
                    ForEach(taskStore.lists, id: \.self) { list in
                        NavigationLink(value: SidebarSection.list(list)) {
                            Label {
                                Text(list)
                                    .font(.system(size: 13))
                            } icon: {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(taskStore.colorForList(list))
                            }
                            .badge(taskStore.countForList(list))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .contextMenu {
                            if list != "General" {
                                Button(role: .destructive) {
                                    taskStore.deleteList(name: list)
                                } label: {
                                    Label("Delete '\(list)'", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    HStack(alignment: .center, spacing: 0) {
                        Text("Lists")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        SidebarAddButton {
                            isShowingNewListSheet = true
                        }
                        .offset(y: 2.5)
                        .padding(.trailing, 10)
                    }
                }
                .collapsible(false)
            }
            .listStyle(.sidebar)

            Divider()

            // Bottom Quick Stats & Settings
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TODAY'S PROGRESS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("\(taskStore.completedTasks.count) tasks completed")
                        .font(.system(size: 11, weight: .medium))
                }
                Spacer()

                Button(action: {
                    WindowManager.shared.showSettings()
                }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(5)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Settings & Supabase Configuration (Cmd+,)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.03))
        }
        .sheet(isPresented: $isShowingNewListSheet) {
            NewListDialogView(taskStore: taskStore, onClose: {
                isShowingNewListSheet = false
            })
        }
    }

    private func boardColor(for board: TaskBoard) -> Color {
        switch board {
        case .today: return .orange
        case .upcoming: return .blue
        case .backlog: return .purple
        case .done: return .green
        }
    }
}

// MARK: - Sidebar Add Button with Native Hover State & Proper Alignment
private struct SidebarAddButton: View {
    var action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isHovered ? Color.primary : Color.secondary)
                .frame(width: 18, height: 18)
                .background(isHovered ? Color.primary.opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help("Add New List")
    }
}
