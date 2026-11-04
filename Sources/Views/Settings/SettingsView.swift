import SwiftUI
import AppKit

public enum SettingsCategory: String, CaseIterable, Identifiable, Sendable {
    case database = "Database"
    case timer = "Focus Timer"
    case notch = "Dynamic Island"
    case aiAndMcp = "AI & MCP"
    case about = "About"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .database: return "cylinder.split.1x2"
        case .timer: return "timer"
        case .notch: return "menubar.arrow.up.rectangle"
        case .aiAndMcp: return "sparkles"
        case .about: return "info.circle"
        }
    }

    public var iconColor: Color {
        switch self {
        case .database: return .blue
        case .timer: return .orange
        case .notch: return .purple
        case .aiAndMcp: return Color(red: 0.65, green: 0.35, blue: 0.98)
        case .about: return .gray
        }
    }
}

public struct SettingsView: View {
    @Bindable var settings = AppSettings.shared
    @Bindable var taskStore: TaskStore
    @Bindable var mcpService = MCPServerService.shared

    @State private var selectedCategory: SettingsCategory = .aiAndMcp
    @State private var aiSubTab: Int = 0 // 0: MCP Server, 1: AI Assistant

    // Supabase state
    @State private var connectionStatus: String? = nil
    @State private var isTestingConnection = false
    @State private var isSyncing = false
    @State private var isSuccess = false

    // AI state
    @State private var aiTestStatus: String? = nil
    @State private var isTestingAI = false
    @State private var isAISuccess = false
    @State private var sampleBreakdownResult: [String] = []
    @State private var isRunningSampleBreakdown = false
    @State private var showAPIKey = false

    // MCP state
    @State private var mcpPortText: String = "4040"
    @State private var copiedConfigType: String? = nil
    @State private var expandedTool: String? = nil
    @State private var configRefreshID = UUID()

    public init(taskStore: TaskStore) {
        self.taskStore = taskStore
        self._mcpPortText = State(initialValue: String(AppSettings.shared.mcpServerPort))
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Sidebar Navigation
            sidebarView
                .frame(width: 200)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.7))

            Divider()
                .opacity(0.15)

            // Content Area
            VStack(spacing: 0) {
                // Top Header Bar
                contentHeaderBar

                Divider()
                    .opacity(0.12)

                // Category Body
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch selectedCategory {
                        case .database:
                            databaseSettingsView
                        case .timer:
                            timerSettingsView
                        case .notch:
                            notchSettingsView
                        case .aiAndMcp:
                            aiAndMCPSettingsView
                        case .about:
                            aboutSettingsView
                        }
                    }
                    .padding(24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        }
        .frame(width: 740, height: 560)
        .preferredColorScheme(.dark)
        .onAppear {
            mcpPortText = String(settings.mcpServerPort)
        }
    }

    // MARK: - Sidebar View
    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cocoa Header
            HStack(spacing: 10) {
                if let logo = NSImage(contentsOf: Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/CocoaLogo.png")) {
                    Image(nsImage: logo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(LinearGradient(
                                colors: [Color.orange.opacity(0.8), Color.purple.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 32, height: 32)
                        Image(systemName: "target")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Cocoa")
                        .font(.system(size: 14, weight: .bold))
                    Text("Preferences")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()
                .opacity(0.15)
                .padding(.horizontal, 12)

            // Navigation Items
            VStack(spacing: 4) {
                ForEach(SettingsCategory.allCases) { category in
                    SettingsSidebarItemView(
                        category: category,
                        isSelected: selectedCategory == category,
                        isMCPServerRunning: mcpService.isRunning,
                        onSelect: {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                selectedCategory = category
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)

            Spacer()

            // Footer Status
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(mcpService.isRunning ? Color.green : Color.gray.opacity(0.5))
                        .frame(width: 7, height: 7)
                    Text(mcpService.isRunning ? "MCP Server Active" : "MCP Offline")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(mcpService.isRunning ? Color.green : Color.secondary)
                }
                Text("\(taskStore.tasks.count) local tasks")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Content Header Bar
    private var contentHeaderBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedCategory.rawValue)
                    .font(.system(size: 18, weight: .bold))

                Text(categorySubtitle(selectedCategory))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if selectedCategory == .aiAndMcp {
                Picker("", selection: $aiSubTab) {
                    Text("MCP Server").tag(0)
                    Text("AI Assistant").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 64)
    }

    private func categorySubtitle(_ category: SettingsCategory) -> String {
        switch category {
        case .database: return "Configure Supabase multi-device sync or offline storage."
        case .timer: return "Customize Pomodoro durations, breaks, and audio cues."
        case .notch: return "Tailor MacBook camera notch integration and interaction behavior."
        case .aiAndMcp: return "MCP server & AI assistant provider settings."
        case .about: return "Cocoa version, system statistics, and keyboard shortcuts."
        }
    }

    // MARK: - 1. AI & MCP Server View
    @ViewBuilder
    private var aiAndMCPSettingsView: some View {
        if aiSubTab == 0 {
            mcpServerSection
        } else {
            aiAssistantSection
        }
    }

    // Sub-tab 0: Model Context Protocol (MCP)
    private var mcpServerSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Status Hero Card
            settingsCard {
                HStack(alignment: .center, spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(mcpService.isRunning ? Color.green.opacity(0.15) : Color.gray.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: mcpService.isRunning ? "network" : "network.slash")
                            .font(.system(size: 20))
                            .foregroundStyle(mcpService.isRunning ? Color.green : Color.gray)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(mcpService.isRunning ? "MCP Server Active" : "MCP Server Stopped")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(mcpService.isRunning ? Color.green : Color.primary)

                            if mcpService.isRunning {
                                Text(":\(mcpService.currentPort)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.2))
                                    .clipShape(Capsule())
                            }
                        }

                        Text(mcpService.isRunning
                             ? "Accepting connections on http://127.0.0.1:\(mcpService.currentPort)/mcp"
                             : "Enable to allow AI assistants (Claude, Cursor, Antigravity) to manage tasks & timers.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { settings.isMCPServerEnabled },
                        set: { enabled in
                            settings.isMCPServerEnabled = enabled
                            if enabled {
                                mcpService.start()
                            } else {
                                mcpService.stop()
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                }
            }

            // Port & Network Controls
            if settings.isMCPServerEnabled {
                settingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        cardSectionTitle("SERVER CONFIGURATION", icon: "slider.horizontal.3")

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Local HTTP Port")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)

                                HStack {
                                    TextField("4040", text: $mcpPortText)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 90)
                                        .font(.system(size: 12, design: .monospaced))

                                    Button("Apply & Restart") {
                                        if let p = Int(mcpPortText), p > 1024 && p < 65535 {
                                            mcpService.restart(port: p)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Activity Stats")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)

                                Text("\(mcpService.requestCount) calls processed")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.primary)
                            }
                        }

                        if !mcpService.lastRequestSummary.isEmpty {
                            Text(mcpService.lastRequestSummary)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 2)
                        }
                    }
                }
            }

            // Client Configuration Exporters
            settingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    cardSectionTitle("CONNECT YOUR AI CLIENT", icon: "link")

                    Text("Copy and paste these pre-built configuration snippets into your AI tool to connect directly to Cocoa.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 10) {
                        clientConfigRow(
                            title: "Claude Desktop",
                            subtitle: "claude_desktop_config.json (Standard stdio transport)",
                            badge: "Anthropic",
                            badgeColor: .orange,
                            target: .claude
                        )

                        clientConfigRow(
                            title: "Cursor IDE",
                            subtitle: "Add to Cursor Settings > Features > MCP (SSE transport)",
                            badge: "Cursor",
                            badgeColor: .blue,
                            target: .cursor
                        )

                        clientConfigRow(
                            title: "Antigravity / Windsurf",
                            subtitle: "Add to antigravity mcpServers configuration",
                            badge: "Agent",
                            badgeColor: .purple,
                            target: .antigravity
                        )
                    }
                    .id(configRefreshID)
                }
            }

            // Exposed Tools Inspector
            settingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    cardSectionTitle("EXPOSED MCP TOOLS & CAPABILITIES (9)", icon: "wrench.and.screwdriver")

                    Text("External AI agents can discover and execute these native tools to manage your Cocoa session:")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 6) {
                        ForEach(mcpService.availableToolsList(), id: \.description) { tool in
                            let toolName = tool["name"] as? String ?? ""
                            let toolDesc = tool["description"] as? String ?? ""
                            let isExpanded = expandedTool == toolName

                            VStack(alignment: .leading, spacing: 4) {
                                Button(action: {
                                    withAnimation(.spring(response: 0.25)) {
                                        expandedTool = isExpanded ? nil : toolName
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "cube.fill")
                                            .font(.system(size: 9))
                                            .foregroundStyle(Color.purple)

                                        Text(toolName)
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            .foregroundStyle(.primary)

                                        Spacer()

                                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)

                                if isExpanded {
                                    Text(toolDesc)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .padding(.leading, 16)
                                        .padding(.bottom, 4)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.02))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
        }
    }

    private func clientConfigRow(title: String, subtitle: String, badge: String, badgeColor: Color, target: AIClientTarget) -> some View {
        let isConfigured = target.isConfigured

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))

                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(badgeColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(badgeColor.opacity(0.15))
                        .clipShape(Capsule())
                }

                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: {
                try? mcpService.installMCP(to: target)
                configRefreshID = UUID()
            }) {
                HStack(spacing: 5) {
                    Image(systemName: isConfigured ? "checkmark" : "bolt.fill")
                    Text(isConfigured ? "Applied" : "Apply")
                }
                .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // Sub-tab 1: AI Assistant Provider
    private var aiAssistantSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Provider Selection Card
            settingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    cardSectionTitle("AI PROVIDER", icon: "brain.head.profile")

                    Picker("", selection: $settings.aiProvider) {
                        ForEach(AIProviderChoice.allCases) { provider in
                            HStack {
                                Image(systemName: provider.iconName)
                                Text(provider.displayName)
                            }
                            .tag(provider)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: settings.aiProvider) { _, newProvider in
                        settings.aiModel = newProvider.defaultModel
                    }

                    Text("Selected model powers 'AI Subtask Breakdown' and smart focus assistance.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            // Credentials & Model Card
            settingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    cardSectionTitle("CREDENTIALS & MODEL", icon: "key.fill")

                    // API Key Field (unless Ollama)
                    if settings.aiProvider != .ollama {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(settings.aiProvider.displayName.uppercased()) API KEY")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)

                            HStack {
                                if showAPIKey {
                                    TextField("sk-...", text: $settings.aiAPIKey)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 12, design: .monospaced))
                                } else {
                                    SecureField("sk-...", text: $settings.aiAPIKey)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 12, design: .monospaced))
                                }

                                Button(action: { showAPIKey.toggle() }) {
                                    Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Model Selector / Presets
                    VStack(alignment: .leading, spacing: 6) {
                        Text("MODEL NAME")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)

                        TextField(settings.aiProvider.defaultModel, text: $settings.aiModel)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))

                        // Quick suggestion pills
                        HStack(spacing: 6) {
                            Text("Suggestions:")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)

                            ForEach(settings.aiProvider.suggestedModels, id: \.self) { modelName in
                                Button(modelName) {
                                    settings.aiModel = modelName
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 10))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(settings.aiModel == modelName ? Color.purple.opacity(0.3) : Color.white.opacity(0.06))
                                .foregroundStyle(settings.aiModel == modelName ? Color.purple : Color.secondary)
                                .clipShape(Capsule())
                            }
                        }
                        .padding(.top, 2)
                    }

                    // Base URL (for Ollama or Custom)
                    if settings.aiProvider == .ollama || settings.aiProvider == .custom {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("CUSTOM BASE URL")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)

                            TextField("http://localhost:11434/v1", text: $settings.aiCustomBaseURL)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                        }
                    }

                    // Test AI Connection Button
                    HStack(spacing: 12) {
                        Button(action: testAIConnection) {
                            HStack(spacing: 6) {
                                if isTestingAI {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "bolt.badge.automatic.fill")
                                }
                                Text(isTestingAI ? "Connecting..." : "Test AI Connection")
                            }
                            .frame(minWidth: 140)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.purple)
                        .disabled(isTestingAI || !settings.isAIConfigured)

                        if let status = aiTestStatus {
                            HStack(spacing: 6) {
                                Image(systemName: isAISuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(isAISuccess ? Color.green : Color.red)
                                Text(status)
                                    .font(.system(size: 11))
                                    .foregroundStyle(isAISuccess ? Color.green : Color.red)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(isAISuccess ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .padding(.top, 4)
                }
            }

            // System Prompt Customization
            settingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    cardSectionTitle("AI FOCUS COACH PERSONA", icon: "bubble.left.and.bubble.right.fill")

                    Text("Custom instructions given to the AI when decomposing complex tasks into subtasks:")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    TextEditor(text: $settings.aiSystemPrompt)
                        .font(.system(size: 11))
                        .frame(height: 70)
                        .padding(6)
                        .background(Color.black.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                        )

                    // Interactive test breakdown
                    HStack {
                        Button(action: runSampleBreakdown) {
                            HStack(spacing: 5) {
                                if isRunningSampleBreakdown {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Image(systemName: "sparkles")
                                }
                                Text("Try Sample Breakdown")
                            }
                            .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isRunningSampleBreakdown || !settings.isAIConfigured)

                        Spacer()
                    }

                    if !sampleBreakdownResult.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sample Breakdown Output:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            ForEach(sampleBreakdownResult, id: \.self) { item in
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.square")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.purple)
                                    Text(item)
                                        .font(.system(size: 11))
                                }
                            }
                        }
                        .padding(8)
                        .background(Color.purple.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }

    // MARK: - 2. Database & Cloud Sync View
    private var databaseSettingsView: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Mode Status Card
            settingsCard {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(settings.isCloudSyncEnabled ? Color.blue.opacity(0.15) : Color.orange.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: settings.isCloudSyncEnabled ? "icloud.fill" : "internaldrive.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(settings.isCloudSyncEnabled ? Color.blue : Color.orange)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(settings.isCloudSyncEnabled ? "Supabase Cloud Sync Mode" : "Local Storage Mode (100% Offline)")
                            .font(.system(size: 14, weight: .bold))

                        Text(settings.isCloudSyncEnabled
                             ? "Tasks synchronize seamlessly with your PostgreSQL database in Supabase."
                             : "All tasks and timers persist locally on this Mac: ~/Library/Application Support/Cocoa/tasks.json")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: $settings.isCloudSyncEnabled)
                        .toggleStyle(.switch)
                }
            }

            if settings.isCloudSyncEnabled {
                settingsCard {
                    VStack(alignment: .leading, spacing: 14) {
                        cardSectionTitle("SUPABASE CREDENTIALS", icon: "key.horizontal.fill")

                        VStack(alignment: .leading, spacing: 4) {
                            Text("PROJECT URL")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)

                            TextField("https://your-project.supabase.co", text: $settings.supabaseURL)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("ANON PUBLIC API KEY")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)

                            TextField("eyJhbGciOi...", text: $settings.supabaseAnonKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(Color.orange)
                            Text("Automatic Schema Migration: Tables and columns are discovered and validated during sync. No manual SQL required.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 2)

                        HStack(spacing: 12) {
                            Button(action: testConnection) {
                                HStack(spacing: 6) {
                                    if isTestingConnection {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Image(systemName: "bolt.horizontal.fill")
                                    }
                                    Text("Test Connection")
                                }
                                .frame(minWidth: 120)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isTestingConnection || !settings.isSupabaseConfigured)

                            Button(action: triggerManualSync) {
                                HStack(spacing: 6) {
                                    if isSyncing {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                    }
                                    Text("Sync Now")
                                }
                                .frame(minWidth: 100)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isSyncing || !settings.isSupabaseConfigured)
                        }

                        if let status = connectionStatus {
                            HStack(spacing: 6) {
                                Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(isSuccess ? Color.green : Color.red)
                                Text(status)
                                    .font(.system(size: 11))
                                    .foregroundStyle(isSuccess ? Color.green : Color.red)
                            }
                            .padding(8)
                            .background(isSuccess ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
        }
    }

    // MARK: - 3. Focus Timer View
    private var timerSettingsView: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Durations Card
            settingsCard {
                VStack(alignment: .leading, spacing: 16) {
                    cardSectionTitle("SESSION DURATIONS", icon: "timer")

                    // Focus Session
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Focus Session Duration")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text("\(settings.pomoWorkMinutes) mins")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.orange)
                        }

                        HStack(spacing: 8) {
                            ForEach([15, 25, 45, 60, 90], id: \.self) { mins in
                                presetButton("\(mins)m", isSelected: settings.pomoWorkMinutes == mins) {
                                    settings.pomoWorkMinutes = mins
                                }
                            }
                        }

                        Slider(value: Binding(
                            get: { Double(settings.pomoWorkMinutes) },
                            set: { settings.pomoWorkMinutes = Int($0) }
                        ), in: 5...120, step: 5)
                    }

                    Divider().opacity(0.1)

                    // Short Break
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Short Break Duration")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text("\(settings.pomoBreakMinutes) mins")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.green)
                        }

                        HStack(spacing: 8) {
                            ForEach([3, 5, 10, 15], id: \.self) { mins in
                                presetButton("\(mins)m", isSelected: settings.pomoBreakMinutes == mins) {
                                    settings.pomoBreakMinutes = mins
                                }
                            }
                        }

                        Slider(value: Binding(
                            get: { Double(settings.pomoBreakMinutes) },
                            set: { settings.pomoBreakMinutes = Int($0) }
                        ), in: 1...30, step: 1)
                    }
                }
            }

            // Audio & Feedback Card
            settingsCard {
                VStack(alignment: .leading, spacing: 16) {
                    cardSectionTitle("AUDIO & ALERTS", icon: "speaker.wave.2.fill")

                    // Master Toggle
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable Sound Effects")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Play sound effects during focus sessions, tasks, and notifications.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: $settings.soundEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }

                    if settings.soundEnabled {
                        Divider().opacity(0.12)

                        // 1. Success Sound Effect
                        soundEffectRow(
                            title: "Success Sound Effect",
                            subtitle: "Triggered on task completion or successful Pomodoro session",
                            icon: "checkmark.seal.fill",
                            iconColor: .green,
                            isEnabled: $settings.isSuccessSoundEnabled,
                            selectedSound: $settings.successSound
                        )

                        Divider().opacity(0.12)

                        // 2. Alert During Tasks
                        soundEffectRow(
                            title: "Alert During Tasks",
                            subtitle: "Triggered during task interval reminders or focus alert cues",
                            icon: "bell.badge.fill",
                            iconColor: .orange,
                            isEnabled: $settings.isTaskAlertSoundEnabled,
                            selectedSound: $settings.taskAlertSound
                        )

                        Divider().opacity(0.12)

                        // 3. Notification Alert
                        soundEffectRow(
                            title: "Notification Alert",
                            subtitle: "Triggered on AI assistant responses, sync events, and alerts",
                            icon: "bubble.left.and.exclamationmark.bubble.right.fill",
                            iconColor: .purple,
                            isEnabled: $settings.isNotificationSoundEnabled,
                            selectedSound: $settings.notificationSound
                        )

                        Divider().opacity(0.12)

                        // Quick Audition Pill Bar
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Quick Sound Audition:")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(SoundManager.availableSounds) { sound in
                                        soundTestButton("\(sound.name) \(sound.emoji)", soundName: sound.id)
                                    }
                                }
                            }
                        }
                        .padding(.top, 2)
                    }
                }
            }

            // Custom Sounds (Local) Card
            settingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    cardSectionTitle("CUSTOM SOUND EFFECTS (LOCAL)", icon: "waveform.and.magnifyingglass")

                    Text("Import your own audio clips (.mp3, .wav, .m4a, .aiff) saved locally on this Mac: ~/Library/Application Support/Cocoa/Sounds/. These can be selected as your Success, Alert, or Notification sound.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Button(action: {
                            SoundManager.shared.promptImportCustomSound { newSound in
                                if let newSound {
                                    SoundManager.shared.playNamedSound(newSound.id)
                                }
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                Text("Import Audio File...")
                            }
                            .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button(action: {
                            SoundManager.shared.revealCustomSoundsInFinder()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "folder.fill")
                                Text("Open in Finder")
                            }
                            .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if SoundManager.shared.customSounds.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "music.note")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                            Text("No custom sounds imported yet. Click 'Import Audio File' or drop your favorite audio files into the Cocoa Sounds folder.")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(Color.white.opacity(0.02))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        Divider().opacity(0.12)

                        VStack(spacing: 8) {
                            ForEach(SoundManager.shared.customSounds) { sound in
                                HStack(spacing: 10) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(Color.orange.opacity(0.15))
                                            .frame(width: 28, height: 28)
                                        Image(systemName: "waveform")
                                            .font(.system(size: 13))
                                            .foregroundStyle(Color.orange)
                                    }

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(sound.name)
                                            .font(.system(size: 12, weight: .semibold))
                                        Text(sound.description)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    // Quick test
                                    Button(action: {
                                        SoundManager.shared.playNamedSound(sound.id)
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "speaker.wave.2.fill")
                                                .font(.system(size: 9))
                                            Text("Play")
                                                .font(.system(size: 10, weight: .medium))
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.white.opacity(0.08))
                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                    }
                                    .buttonStyle(.plain)

                                    // Delete
                                    Button(action: {
                                        SoundManager.shared.deleteCustomSound(id: sound.id)
                                    }) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 10))
                                            .foregroundStyle(Color.red.opacity(0.7))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Delete local audio file")
                                }
                                .padding(8)
                                .background(Color.white.opacity(0.03))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }
            }
        }
    }

    private func soundEffectRow(
        title: String,
        subtitle: String,
        icon: String,
        iconColor: Color,
        isEnabled: Binding<Bool>,
        selectedSound: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(iconColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            if isEnabled.wrappedValue {
                HStack(spacing: 10) {
                    Picker("", selection: selectedSound) {
                        if !SoundManager.shared.customSounds.isEmpty {
                            Section("Custom Local Sounds") {
                                ForEach(SoundManager.shared.customSounds) { sound in
                                    Text("\(sound.emoji)  \(sound.name) — \(sound.description)")
                                        .tag(sound.id)
                                }
                            }
                        }

                        Section("macOS System Sounds") {
                            ForEach(SoundManager.systemSounds) { sound in
                                Text("\(sound.emoji)  \(sound.name) — \(sound.description)")
                                    .tag(sound.id)
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)

                    Button(action: {
                        SoundManager.shared.playNamedSound(selectedSound.wrappedValue)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 10))
                            Text("Preview")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 42)
            }
        }
    }

    private func presetButton(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .bold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? Color.orange.opacity(0.3) : Color.white.opacity(0.06))
                .foregroundStyle(isSelected ? Color.orange : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func soundTestButton(_ label: String, soundName: String) -> some View {
        Button(action: {
            SoundManager.shared.playNamedSound(soundName)
        }) {
            HStack(spacing: 4) {
                Image(systemName: "play.fill")
                    .font(.system(size: 8))
                Text(label)
            }
            .font(.system(size: 11))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: - 4. Dynamic Island View
    private var notchSettingsView: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Appearance Card
            settingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    cardSectionTitle("NOTCH PILL APPEARANCE", icon: "macbook.and.iphone")

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Left Ear Display Style")
                            .font(.system(size: 12, weight: .medium))

                        Picker("", selection: $settings.notchLeftStyle) {
                            ForEach(NotchLeftStyle.allCases) { style in
                                Text(style.label).tag(style)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    HStack(spacing: 20) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(red: 1.0, green: 0.80, blue: 0.12))
                                .frame(width: 8, height: 8)
                            Text("Yellow Dot: Active Focus Timer")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(red: 0.20, green: 0.85, blue: 0.45))
                                .frame(width: 8, height: 8)
                            Text("Green Dot: Idle / Rest Mode")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
            }

            // Interaction & Shield Card
            settingsCard {
                VStack(alignment: .leading, spacing: 14) {
                    cardSectionTitle("INTERACTION & SHIELD", icon: "shield.lefthalf.filled")

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Hover Open Delay")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text(String(format: "%.2fs", settings.hoverDelaySeconds))
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.purple)
                        }

                        Slider(value: $settings.hoverDelaySeconds, in: 0.15...0.8, step: 0.05)

                        Text("Prevents accidental triggers when cursor sweeps across the top macOS menu bar.")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }

                    Divider().opacity(0.1)

                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Shield While Timer Running (Click Only to Open)", isOn: $settings.isNotchShieldEnabled)
                            .toggleStyle(.switch)
                            .font(.system(size: 12, weight: .medium))

                        Text("When focus timer is ticking, hovering will never expand the Dynamic Island, eliminating all distractions.")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: - 5. About View
    private var aboutSettingsView: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsCard {
                HStack(spacing: 18) {
                    if let logo = NSImage(contentsOf: Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/CocoaLogo.png")) {
                        Image(nsImage: logo)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    colors: [Color.orange, Color.purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .frame(width: 64, height: 64)
                            Image(systemName: "target")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Cocoa")
                            .font(.system(size: 22, weight: .bold))
                        Text("Version 1.0.0 (Native Swift 6 / SwiftUI + AppKit)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text("Native macOS Focus & Task Companion with MacBook Notch Dynamic Island & Model Context Protocol.")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            // Quick Stats
            settingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    cardSectionTitle("WORKSPACE STATISTICS", icon: "chart.bar.fill")

                    HStack(spacing: 24) {
                        statItem(label: "Total Tasks", value: "\(taskStore.tasks.count)")
                        statItem(label: "Today Board", value: "\(taskStore.todayTasks.count)")
                        statItem(label: "Completed", value: "\(taskStore.completedTasks.count)")
                        statItem(label: "Lists", value: "\(taskStore.lists.count)")
                    }
                }
            }

            // Shortcuts Cheat Sheet
            settingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    cardSectionTitle("KEYBOARD SHORTCUTS", icon: "keyboard.fill")

                    VStack(spacing: 6) {
                        shortcutRow("Cmd + 1", desc: "Open Main Dashboard")
                        shortcutRow("Cmd + 2", desc: "Focus in Notch Pill (Dynamic Island)")
                        shortcutRow("Cmd + 3", desc: "Open Floating Tower Mode")
                        shortcutRow("Cmd + ,", desc: "Open Cocoa Settings")
                        shortcutRow("Cmd + B / I / U", desc: "Rich Notes Bold / Italic / Underline")
                        shortcutRow("Cmd + Shift + C", desc: "Monospace Code chip in Notes")
                    }
                }
            }
        }
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.orange)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 80)
    }

    private func shortcutRow(_ key: String, desc: String) -> some View {
        HStack {
            Text(key)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Spacer()

            Text(desc)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Reusable Card Styling
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 0.8)
        )
    }

    private func cardSectionTitle(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 2)
    }

    // MARK: - Actions
    private func copyToClipboard(_ text: String, type: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedConfigType = type
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if copiedConfigType == type {
                copiedConfigType = nil
            }
        }
    }

    private func testAIConnection() {
        isTestingAI = true
        aiTestStatus = "Testing connection to \(settings.aiModel)..."
        isAISuccess = false

        Task {
            do {
                let reply = try await AIService.shared.testConnection()
                await MainActor.run {
                    self.aiTestStatus = "Connected: \(reply)"
                    self.isAISuccess = true
                    self.isTestingAI = false
                }
            } catch {
                await MainActor.run {
                    self.aiTestStatus = "Failed: \(error.localizedDescription)"
                    self.isAISuccess = false
                    self.isTestingAI = false
                }
            }
        }
    }

    private func runSampleBreakdown() {
        isRunningSampleBreakdown = true
        sampleBreakdownResult = []

        Task {
            do {
                let res = try await AIService.shared.breakdownTask(
                    title: "Prepare quarterly product presentation",
                    notes: "Include metrics, roadmap, and design mockups."
                )
                await MainActor.run {
                    self.sampleBreakdownResult = res
                    self.isRunningSampleBreakdown = false
                }
            } catch {
                await MainActor.run {
                    self.sampleBreakdownResult = ["Error: \(error.localizedDescription)"]
                    self.isRunningSampleBreakdown = false
                }
            }
        }
    }

    private func testConnection() {
        settings.save()
        isTestingConnection = true
        connectionStatus = "Testing connection & validating schema..."
        isSuccess = false

        Task {
            do {
                let msg = try await SupabaseSyncService.shared.testConnection()
                await MainActor.run {
                    self.connectionStatus = msg
                    self.isSuccess = true
                    self.isTestingConnection = false
                }
            } catch {
                await MainActor.run {
                    self.connectionStatus = "Failed: \(error.localizedDescription)"
                    self.isSuccess = false
                    self.isTestingConnection = false
                }
            }
        }
    }

    private func triggerManualSync() {
        settings.save()
        isSyncing = true
        connectionStatus = "Syncing & running schema migration..."
        isSuccess = true

        Task {
            do {
                try await SupabaseSyncService.shared.ensureSchemaMigrated()
                try await SupabaseSyncService.shared.pushTasks(taskStore.tasks)
                let remote = try await SupabaseSyncService.shared.fetchTasks()

                await MainActor.run {
                    taskStore.mergeRemoteTasks(remote)
                    self.connectionStatus = "Sync Complete! (\(taskStore.tasks.count) tasks up to date)"
                    self.isSuccess = true
                    self.isSyncing = false
                }
            } catch {
                await MainActor.run {
                    self.connectionStatus = "Sync Failed: \(error.localizedDescription)"
                    self.isSuccess = false
                    self.isSyncing = false
                }
            }
        }
    }
}

// MARK: - Fully Clickable & Hoverable Settings Sidebar Item
private struct SettingsSidebarItemView: View {
    let category: SettingsCategory
    let isSelected: Bool
    let isMCPServerRunning: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(category.iconColor.opacity(isSelected ? 0.9 : 0.15))
                        .frame(width: 24, height: 24)
                    Image(systemName: category.iconName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : category.iconColor)
                }

                Text(category.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.85))

                Spacer()

                if category == .aiAndMcp && isMCPServerRunning {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.14) : (isHovered ? Color.white.opacity(0.06) : Color.white.opacity(0.001)))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
