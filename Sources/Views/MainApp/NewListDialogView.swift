import SwiftUI

public enum ListDialogMode: Equatable, Sendable {
    case create
    case edit(originalName: String, currentColor: String)
}

public struct EditableListTarget: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let color: String

    public init(name: String, color: String) {
        self.name = name
        self.color = color
    }
}

public struct NewListDialogView: View {
    @Bindable var taskStore: TaskStore
    public var mode: ListDialogMode
    public var onClose: () -> Void

    @State private var name: String
    @State private var selectedColor: ListColorChoice
    @FocusState private var isInputFocused: Bool

    public init(taskStore: TaskStore, mode: ListDialogMode = .create, onClose: @escaping () -> Void) {
        self.taskStore = taskStore
        self.mode = mode
        self.onClose = onClose
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _selectedColor = State(initialValue: .orange)
        case .edit(let originalName, let currentColor):
            _name = State(initialValue: originalName)
            _selectedColor = State(initialValue: ListColorChoice(rawValue: currentColor) ?? .orange)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Clean Text Header - ZERO big icons
            Text(isEditing ? "Edit List" : "New List")
                .font(.system(size: 15, weight: .bold))

            // Input Fields Section
            VStack(alignment: .leading, spacing: 14) {
                // List Name Input
                VStack(alignment: .leading, spacing: 6) {
                    Text("NAME")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)

                    TextField("List Name", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(isInputFocused ? selectedColor.color.opacity(0.8) : Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .focused($isInputFocused)
                        .onSubmit {
                            submit()
                        }
                }

                // Color Selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("COLOR")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 7) {
                        ForEach(ListColorChoice.allCases) { choice in
                            ZStack {
                                Circle()
                                    .fill(choice.color)
                                    .frame(width: 22, height: 22)

                                if selectedColor == choice {
                                    Circle()
                                        .strokeBorder(Color.white, lineWidth: 2)
                                        .frame(width: 28, height: 28)

                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .contentShape(Circle())
                            .onTapGesture {
                                selectedColor = choice
                            }
                        }
                    }
                }
            }

            // Footer Action Buttons
            HStack(spacing: 10) {
                Button(action: {
                    onClose()
                }) {
                    Text("Cancel")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .keyboardShortcut(.cancelAction)

                Button(action: {
                    submit()
                }) {
                    Text(isEditing ? "Save Changes" : "Add List")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.3) : selectedColor.color)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 330)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isInputFocused = true
            }
        }
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        switch mode {
        case .create:
            taskStore.addList(name: trimmed, color: selectedColor.rawValue)
            taskStore.selectedSection = .list(trimmed)
        case .edit(let originalName, _):
            taskStore.updateList(oldName: originalName, newName: trimmed, newColor: selectedColor.rawValue)
        }
        onClose()
    }
}
