import SwiftUI

public enum NotchTab: String, CaseIterable, Identifiable, Sendable {
    case subtasks = "Subtasks"
    case notes = "Notes"
    case upNext = "Up Next"

    public var id: String { rawValue }
}

public struct NotchPillView: View {
    @Bindable var taskStore: TaskStore
    @Bindable var timerManager: TimerManager
    public var onDetachToFloating: () -> Void
    public var onOpenMainApp: () -> Void
    public var onIslandBoundsChanged: (CGFloat, CGFloat) -> Void

    @State private var isExpanded: Bool = false
    @State private var isHovering: Bool = false
    @State private var hoverTask: DispatchWorkItem? = nil
    @State private var closeTask: DispatchWorkItem? = nil
    @State private var selectedTab: NotchTab = .subtasks
    @State private var newSubtaskText: String = ""

    private let notchGeo = NotchDetector.currentNotchGeometry()

    // Configurable delays
    private var openHoverDelay: TimeInterval { AppSettings.shared.hoverDelaySeconds }
    private let closeHoverDelay: TimeInterval = 0.40

    public init(
        taskStore: TaskStore,
        timerManager: TimerManager,
        onDetachToFloating: @escaping () -> Void,
        onOpenMainApp: @escaping () -> Void,
        onIslandBoundsChanged: @escaping (CGFloat, CGFloat) -> Void
    ) {
        self.taskStore = taskStore
        self.timerManager = timerManager
        self.onDetachToFloating = onDetachToFloating
        self.onOpenMainApp = onOpenMainApp
        self.onIslandBoundsChanged = onIslandBoundsChanged
    }

    private var currentWidth: CGFloat {
        isExpanded ? notchGeo.expandedWidth : notchGeo.compactIslandWidth
    }

    private var currentHeight: CGFloat {
        isExpanded ? notchGeo.expandedHeight : notchGeo.compactIslandHeight
    }

    public var body: some View {
        VStack(spacing: 0) {
            Group {
                if isExpanded {
                    expandedContentView
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                } else {
                    compactPillWingsView
                        .transition(.opacity)
                }
            }
            .frame(width: currentWidth, height: currentHeight, alignment: .top)
            .background {
                if isExpanded {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                }
            }
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: isExpanded ? 24 : 14,
                    bottomTrailingRadius: isExpanded ? 24 : 14,
                    topTrailingRadius: 0,
                    style: .continuous
                )
            )
            // Coucou style: Opacity 0 / transparent in compact menu bar, frosted glass only when expanded!
            .shadow(color: isExpanded ? Color.black.opacity(0.35) : Color.clear, radius: isExpanded ? 20 : 0, x: 0, y: isExpanded ? 10 : 0)
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: isExpanded)
            .contentShape(Rectangle())
            .onHover { hovering in
                handleHover(hovering: hovering)
            }
            .onTapGesture {
                handleClick()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: isExpanded) { _, expanded in
            let w = expanded ? notchGeo.expandedWidth : notchGeo.compactIslandWidth
            let h = expanded ? notchGeo.expandedHeight : notchGeo.compactIslandHeight
            onIslandBoundsChanged(w, h)
        }
        .onAppear {
            onIslandBoundsChanged(notchGeo.compactIslandWidth, notchGeo.compactIslandHeight)
        }
    }

    // MARK: - Compact Pill with Left & Right Wings (Coucou Style!)
    private var compactPillWingsView: some View {
        Group {
            if notchGeo.hasPhysicalNotch {
                // MacBook with physical notch: Wings stick out to the left and right of the camera notch!
                HStack(spacing: 0) {
                    // LEFT WING (Left of the notch)
                    leftEarView
                        .frame(width: notchGeo.earWidth, height: notchGeo.compactIslandHeight)

                    // CENTER GAP (Behind the physical notch - kept blank/black)
                    Color.clear
                        .frame(width: notchGeo.notchWidth, height: notchGeo.compactIslandHeight)

                    // RIGHT WING (Right of the notch)
                    rightEarView
                        .frame(width: notchGeo.earWidth, height: notchGeo.compactIslandHeight)
                }
            } else {
                // External display / No notch: Centered pill
                HStack(spacing: 8) {
                    leftEarView
                    Spacer()
                    rightEarView
                }
                .padding(.horizontal, 10)
                .frame(width: notchGeo.compactIslandWidth, height: notchGeo.compactIslandHeight)
            }
        }
    }

    // MARK: - Status Color Indicator
    private var isFocus: Bool {
        return timerManager.isRunning && !timerManager.isBreak
    }

    private var statusColor: Color {
        if isFocus {
            // Kuning -> focus
            return Color(red: 1.0, green: 0.80, blue: 0.12)
        } else {
            // Hijau -> rest atau timer nya lagi mati
            return Color(red: 0.20, green: 0.85, blue: 0.45)
        }
    }

    // MARK: - Left Ear View
    private var leftEarView: some View {
        HStack(spacing: 6) {
            if AppSettings.shared.notchLeftStyle == .cocoaAndDot {
                Text("🍫")
                    .font(.system(size: 11))
            }

            // Glowing status dot: kuning (focus), hijau (rest/mati)
            ZStack {
                if isFocus {
                    Circle()
                        .fill(statusColor.opacity(0.35))
                        .frame(width: 12, height: 12)
                }

                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                    .shadow(color: statusColor.opacity(isFocus ? 0.8 : 0.4), radius: isFocus ? 3 : 1)
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Right Ear View
    private var rightEarView: some View {
        HStack(spacing: 5) {
            if timerManager.isRunning || timerManager.state == .paused {
                Text(timerManager.formattedTime)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(isFocus ? Color(red: 1.0, green: 0.80, blue: 0.12) : (timerManager.isBreak ? Color(red: 0.20, green: 0.85, blue: 0.45) : Color.white))

                ProgressRing(
                    progress: timerManager.progress,
                    lineWidth: 2.2,
                    ringColor: isFocus ? Color(red: 1.0, green: 0.80, blue: 0.12) : (timerManager.isBreak ? Color(red: 0.20, green: 0.85, blue: 0.45) : Color.gray)
                )
                .frame(width: 12, height: 12)
            } else {
                Text(timerManager.formattedTime)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))

                ProgressRing(
                    progress: 0.0,
                    lineWidth: 2.0,
                    ringColor: Color.white.opacity(0.2)
                )
                .frame(width: 12, height: 12)
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Expanded Content View (Padded below the notch!)
    private var expandedContentView: some View {
        VStack(spacing: 12) {
            // Header Row (Active Task & Mode Detach Buttons)
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Text("🍫")
                        .font(.system(size: 13))
                    Text(taskStore.activeTask?.title ?? "No Active Task")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 8) {
                    // Open Main App
                    Button(action: {
                        collapse()
                        onOpenMainApp()
                    }) {
                        Image(systemName: "macwindow")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(5)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Open Main App Dashboard")

                    // Detach to Floating Tower
                    Button(action: {
                        collapse()
                        onDetachToFloating()
                    }) {
                        Image(systemName: "rectangle.portrait.and.arrow.forward")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(5)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Detach to Floating Tower Card")

                    // Close Button
                    Button(action: collapse) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(5)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            // Big Timer Display & Action Buttons
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(timerManager.formattedTime)
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                        .foregroundStyle(timerManager.isRunning ? Color.orange : Color.white)

                    Text(timerManager.isRunning ? "Focus Session in Progress" : (timerManager.state == .paused ? "Paused" : "Ready to Focus"))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer()

                HStack(spacing: 8) {
                    Button(action: {
                        timerManager.toggle()
                    }) {
                        Image(systemName: timerManager.isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 32, height: 32)
                            .background(Color.orange)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        timerManager.completeCurrentSession()
                    }) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Complete Task")
                }
            }

            // Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 3)

                    Capsule()
                        .fill(Color.orange)
                        .frame(width: geo.size.width * CGFloat(timerManager.progress), height: 3)
                }
            }
            .frame(height: 3)

            // Segmented Tabs: [ Subtasks (x/y) ] [ Notes ] [ Up Next ]
            HStack(spacing: 6) {
                let subtasksCount = taskStore.activeTask?.subtasks.count ?? 0
                let doneCount = taskStore.activeTask?.subtasks.filter(\.isCompleted).count ?? 0
                let subtaskLabel = subtasksCount > 0 ? "Subtasks (\(doneCount)/\(subtasksCount))" : "Subtasks"

                tabButton(title: subtaskLabel, tab: .subtasks)
                tabButton(title: "Notes", tab: .notes)
                tabButton(title: "Up Next", tab: .upNext)
                Spacer()
            }
            .padding(.top, 1)

            // Tab Content - Fixed uniform 160pt height across all tabs!
            Group {
                switch selectedTab {
                case .subtasks:
                    subtasksTabView
                case .notes:
                    notesTabView
                case .upNext:
                    upNextTabView
                }
            }
            .frame(height: 160, alignment: .top)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        // CRITICAL COUCOU FIX: Push down content so it begins cleanly below the physical camera notch
        .padding(.top, notchGeo.hasPhysicalNotch ? (notchGeo.notchHeight + 8) : 10)
    }

    // MARK: - Tab Views (Uniform fixed 160pt height)
    private var subtasksTabView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let active = taskStore.activeTask {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 5) {
                        if active.subtasks.isEmpty {
                            Text("No subtasks yet. Type below to add checkpoints.")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.45))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(active.subtasks) { subtask in
                                HStack(spacing: 8) {
                                    Button(action: {
                                        taskStore.toggleSubtask(in: active.id, subtaskId: subtask.id)
                                    }) {
                                        Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 13))
                                            .foregroundStyle(subtask.isCompleted ? Color.green : Color.white.opacity(0.6))
                                    }
                                    .buttonStyle(.plain)

                                    Text(subtask.title)
                                        .font(.system(size: 12.5))
                                        .strikethrough(subtask.isCompleted)
                                        .foregroundStyle(subtask.isCompleted ? Color.white.opacity(0.4) : Color.white.opacity(0.92))
                                        .lineLimit(1)

                                    Spacer()

                                    Button(action: {
                                        taskStore.deleteSubtask(in: active.id, subtaskId: subtask.id)
                                    }) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 9))
                                            .foregroundStyle(Color.white.opacity(0.35))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 2)
                                .padding(.horizontal, 4)
                            }
                        }
                    }
                }
                .frame(height: 118)

                // Add subtask input bar
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))

                    TextField("Add subtask...", text: $newSubtaskText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white)
                        .onSubmit {
                            let trimmed = newSubtaskText.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                taskStore.addSubtask(to: active.id, title: trimmed)
                                newSubtaskText = ""
                            }
                        }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text("Select an active task to manage subtasks.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 8)
            }
        }
        .frame(height: 160, alignment: .top)
    }

    private var notesTabView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let active = taskStore.activeTask {
                HStack {
                    // Meta tags
                    HStack(spacing: 6) {
                        Text(active.priority.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.12))
                            .foregroundStyle(Color.orange)
                            .clipShape(Capsule())

                        listBadge(for: active.listName)

                        Text("\(active.estimatedMinutes)m")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.1))
                            .foregroundStyle(.white.opacity(0.85))
                            .clipShape(Capsule())
                    }

                    Spacer()
                }

                NativeRichTextEditor(
                    text: Binding(
                        get: { active.notes },
                        set: { newNotes in
                            taskStore.updateNotes(for: active.id, notes: newNotes)
                        }
                    ),
                    taskId: active.id,
                    baseFontSize: 13,
                    minHeight: 110
                )
                .frame(height: 126)
            } else {
                Text("No active task selected.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 8)
            }
        }
        .frame(height: 160, alignment: .top)
    }

    private var upNextTabView: some View {
        VStack(alignment: .leading, spacing: 5) {
            let tasks = taskStore.todayTasks.prefix(5)
            if tasks.isEmpty {
                HStack {
                    Text("No upcoming tasks for today 🎉")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.45))
                    Spacer()
                }
                .padding(.vertical, 12)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(tasks) { task in
                            HStack {
                                Button(action: {
                                    taskStore.toggleCompleted(id: task.id)
                                }) {
                                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 12))
                                        .foregroundStyle(task.isCompleted ? Color.green : Color.white.opacity(0.5))
                                }
                                .buttonStyle(.plain)

                                Text(task.title)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundStyle(Color.white.opacity(0.92))
                                    .lineLimit(1)

                                Spacer()

                                Text(task.formattedEstimate)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.45))
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                            .background(task.id == taskStore.activeTaskId ? Color.white.opacity(0.10) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                taskStore.selectTask(id: task.id)
                                timerManager.syncWithActiveTask()
                            }
                        }
                    }
                }
            }
        }
        .frame(height: 160, alignment: .top)
    }

    private func tabButton(title: String, tab: NotchTab) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                selectedTab = tab
            }
        }) {
            Text(title)
                .font(.system(size: 11, weight: selectedTab == tab ? .bold : .medium))
                .foregroundStyle(selectedTab == tab ? .white : .white.opacity(0.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(selectedTab == tab ? Color.white.opacity(0.16) : Color.white.opacity(0.04))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(selectedTab == tab ? Color.white.opacity(0.18) : Color.clear, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hover & Click Interactions
    private func handleHover(hovering: Bool) {
        isHovering = hovering

        if !hovering {
            hoverTask?.cancel()
            hoverTask = nil

            if isExpanded {
                let task = DispatchWorkItem { [self] in
                    collapse()
                }
                closeTask = task
                DispatchQueue.main.asyncAfter(deadline: .now() + closeHoverDelay, execute: task)
            }
            return
        }

        closeTask?.cancel()
        closeTask = nil

        // USER RULE: "dan selama timer nya jalan ya di hover dynamic island nya ngga akan kebuka kecuali di klik"
        if timerManager.isRunning && AppSettings.shared.isNotchShieldEnabled {
            return
        }

        guard !isExpanded else { return }

        hoverTask?.cancel()
        let task = DispatchWorkItem { [self] in
            expand()
        }
        hoverTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + openHoverDelay, execute: task)
    }

    private func handleClick() {
        hoverTask?.cancel()
        hoverTask = nil
        closeTask?.cancel()
        closeTask = nil

        if isExpanded {
            collapse()
        } else {
            expand()
        }
    }

    private func expand() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
            isExpanded = true
        }
    }

    private func collapse() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            isExpanded = false
        }
    }

    private func listBadge(for listName: String) -> some View {
        let color = taskStore.colorForList(listName)
        return HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 4.5, height: 4.5)
            Text(listName)
                .font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.15))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }
}
