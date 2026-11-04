import Foundation
import Observation

public enum NotchLeftStyle: String, CaseIterable, Identifiable, Sendable {
    case cocoaAndDot = "cocoaAndDot"
    case dotOnly = "dotOnly"

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .cocoaAndDot: return "Cocoa Logo + Status Dot"
        case .dotOnly: return "Status Dot Only"
        }
    }
}

public enum AIProviderChoice: String, CaseIterable, Identifiable, Codable, Sendable {
    case anthropic = "anthropic"
    case openai = "openai"
    case gemini = "gemini"
    case ollama = "ollama"
    case custom = "custom"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .anthropic: return "Anthropic Claude"
        case .openai: return "OpenAI ChatGPT"
        case .gemini: return "Google Gemini"
        case .ollama: return "Ollama (Local LLM)"
        case .custom: return "Custom OpenAI-Compatible"
        }
    }

    public var iconName: String {
        switch self {
        case .anthropic: return "brain.head.profile"
        case .openai: return "sparkles"
        case .gemini: return "wand.and.stars"
        case .ollama: return "desktopcomputer"
        case .custom: return "network"
        }
    }

    public var defaultModel: String {
        switch self {
        case .anthropic: return "claude-3-5-sonnet-latest"
        case .openai: return "gpt-4o-mini"
        case .gemini: return "gemini-2.0-flash"
        case .ollama: return "llama3.2"
        case .custom: return "gpt-4o"
        }
    }

    public var suggestedModels: [String] {
        switch self {
        case .anthropic:
            return ["claude-3-7-sonnet-20250219", "claude-3-5-sonnet-latest", "claude-3-5-haiku-latest"]
        case .openai:
            return ["gpt-4o", "gpt-4o-mini", "o3-mini", "o1-mini"]
        case .gemini:
            return ["gemini-2.0-flash", "gemini-2.0-pro-exp", "gemini-1.5-pro"]
        case .ollama:
            return ["llama3.2", "mistral", "deepseek-r1", "qwen2.5"]
        case .custom:
            return ["gpt-4o", "deepseek-chat", "mistral-large"]
        }
    }
}

public struct AppSettingsPayload: Codable, Sendable {
    public var supabaseURL: String = ""
    public var supabaseAnonKey: String = ""
    public var isCloudSyncEnabled: Bool = false
    public var pomoWorkMinutes: Int = 25
    public var pomoBreakMinutes: Int = 5
    public var soundEnabled: Bool = true
    public var isSuccessSoundEnabled: Bool = true
    public var successSound: String = "Glass"
    public var isTaskAlertSoundEnabled: Bool = true
    public var taskAlertSound: String = "Ping"
    public var isNotificationSoundEnabled: Bool = true
    public var notificationSound: String = "Tink"
    public var hoverDelaySeconds: Double = 0.35
    public var isNotchShieldEnabled: Bool = true
    public var notchLeftStyle: String = NotchLeftStyle.cocoaAndDot.rawValue
    public var isMCPServerEnabled: Bool = true
    public var mcpServerPort: Int = 4040
    public var mcpAuthToken: String = ""
    public var aiProvider: String = AIProviderChoice.anthropic.rawValue
    public var aiAPIKey: String = ""
    public var aiModel: String = ""
    public var aiCustomBaseURL: String = "http://localhost:11434/v1"
    public var aiSystemPrompt: String = "You are Cocoa Focus Assistant. You help organize tasks, break down complex work into clear actionable subtasks, and estimate focus sessions."

    public init(
        supabaseURL: String = "",
        supabaseAnonKey: String = "",
        isCloudSyncEnabled: Bool = false,
        pomoWorkMinutes: Int = 25,
        pomoBreakMinutes: Int = 5,
        soundEnabled: Bool = true,
        isSuccessSoundEnabled: Bool = true,
        successSound: String = "Glass",
        isTaskAlertSoundEnabled: Bool = true,
        taskAlertSound: String = "Ping",
        isNotificationSoundEnabled: Bool = true,
        notificationSound: String = "Tink",
        hoverDelaySeconds: Double = 0.35,
        isNotchShieldEnabled: Bool = true,
        notchLeftStyle: String = NotchLeftStyle.cocoaAndDot.rawValue,
        isMCPServerEnabled: Bool = true,
        mcpServerPort: Int = 4040,
        mcpAuthToken: String = "",
        aiProvider: String = AIProviderChoice.anthropic.rawValue,
        aiAPIKey: String = "",
        aiModel: String = "",
        aiCustomBaseURL: String = "http://localhost:11434/v1",
        aiSystemPrompt: String = "You are Cocoa Focus Assistant. You help organize tasks, break down complex work into clear actionable subtasks, and estimate focus sessions."
    ) {
        self.supabaseURL = supabaseURL
        self.supabaseAnonKey = supabaseAnonKey
        self.isCloudSyncEnabled = isCloudSyncEnabled
        self.pomoWorkMinutes = pomoWorkMinutes
        self.pomoBreakMinutes = pomoBreakMinutes
        self.soundEnabled = soundEnabled
        self.isSuccessSoundEnabled = isSuccessSoundEnabled
        self.successSound = successSound
        self.isTaskAlertSoundEnabled = isTaskAlertSoundEnabled
        self.taskAlertSound = taskAlertSound
        self.isNotificationSoundEnabled = isNotificationSoundEnabled
        self.notificationSound = notificationSound
        self.hoverDelaySeconds = hoverDelaySeconds
        self.isNotchShieldEnabled = isNotchShieldEnabled
        self.notchLeftStyle = notchLeftStyle
        self.isMCPServerEnabled = isMCPServerEnabled
        self.mcpServerPort = mcpServerPort
        self.mcpAuthToken = mcpAuthToken
        self.aiProvider = aiProvider
        self.aiAPIKey = aiAPIKey
        self.aiModel = aiModel
        self.aiCustomBaseURL = aiCustomBaseURL
        self.aiSystemPrompt = aiSystemPrompt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.supabaseURL = try container.decodeIfPresent(String.self, forKey: .supabaseURL) ?? ""
        self.supabaseAnonKey = try container.decodeIfPresent(String.self, forKey: .supabaseAnonKey) ?? ""
        self.isCloudSyncEnabled = try container.decodeIfPresent(Bool.self, forKey: .isCloudSyncEnabled) ?? false
        self.pomoWorkMinutes = try container.decodeIfPresent(Int.self, forKey: .pomoWorkMinutes) ?? 25
        self.pomoBreakMinutes = try container.decodeIfPresent(Int.self, forKey: .pomoBreakMinutes) ?? 5
        let baseSound = try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
        self.soundEnabled = baseSound
        self.isSuccessSoundEnabled = try container.decodeIfPresent(Bool.self, forKey: .isSuccessSoundEnabled) ?? baseSound
        self.successSound = try container.decodeIfPresent(String.self, forKey: .successSound) ?? "Glass"
        self.isTaskAlertSoundEnabled = try container.decodeIfPresent(Bool.self, forKey: .isTaskAlertSoundEnabled) ?? true
        self.taskAlertSound = try container.decodeIfPresent(String.self, forKey: .taskAlertSound) ?? "Ping"
        self.isNotificationSoundEnabled = try container.decodeIfPresent(Bool.self, forKey: .isNotificationSoundEnabled) ?? true
        self.notificationSound = try container.decodeIfPresent(String.self, forKey: .notificationSound) ?? "Tink"
        self.hoverDelaySeconds = try container.decodeIfPresent(Double.self, forKey: .hoverDelaySeconds) ?? 0.35
        self.isNotchShieldEnabled = try container.decodeIfPresent(Bool.self, forKey: .isNotchShieldEnabled) ?? true
        self.notchLeftStyle = try container.decodeIfPresent(String.self, forKey: .notchLeftStyle) ?? NotchLeftStyle.cocoaAndDot.rawValue
        self.isMCPServerEnabled = try container.decodeIfPresent(Bool.self, forKey: .isMCPServerEnabled) ?? true
        self.mcpServerPort = try container.decodeIfPresent(Int.self, forKey: .mcpServerPort) ?? 4040
        self.mcpAuthToken = try container.decodeIfPresent(String.self, forKey: .mcpAuthToken) ?? ""
        self.aiProvider = try container.decodeIfPresent(String.self, forKey: .aiProvider) ?? AIProviderChoice.anthropic.rawValue
        self.aiAPIKey = try container.decodeIfPresent(String.self, forKey: .aiAPIKey) ?? ""
        self.aiModel = try container.decodeIfPresent(String.self, forKey: .aiModel) ?? ""
        self.aiCustomBaseURL = try container.decodeIfPresent(String.self, forKey: .aiCustomBaseURL) ?? "http://localhost:11434/v1"
        self.aiSystemPrompt = try container.decodeIfPresent(String.self, forKey: .aiSystemPrompt) ?? "You are Cocoa Focus Assistant. You help organize tasks, break down complex work into clear actionable subtasks, and estimate focus sessions."
    }
}

@Observable
public final class AppSettings: @unchecked Sendable {
    public static let shared = AppSettings()

    private let settingsFileURL: URL
    private var isInitializing = false

    // Supabase / Database Settings
    public var supabaseURL: String {
        didSet { save() }
    }
    public var supabaseAnonKey: String {
        didSet { save() }
    }
    public var isCloudSyncEnabled: Bool {
        didSet { save() }
    }

    // Timer Settings
    public var pomoWorkMinutes: Int {
        didSet { save() }
    }
    public var pomoBreakMinutes: Int {
        didSet { save() }
    }
    public var soundEnabled: Bool {
        didSet { save() }
    }
    public var isSuccessSoundEnabled: Bool {
        didSet { save() }
    }
    public var successSound: String {
        didSet { save() }
    }
    public var isTaskAlertSoundEnabled: Bool {
        didSet { save() }
    }
    public var taskAlertSound: String {
        didSet { save() }
    }
    public var isNotificationSoundEnabled: Bool {
        didSet { save() }
    }
    public var notificationSound: String {
        didSet { save() }
    }

    // Notch & Dynamic Island Settings
    public var hoverDelaySeconds: Double {
        didSet { save() }
    }
    public var isNotchShieldEnabled: Bool {
        didSet { save() }
    }
    public var notchLeftStyle: NotchLeftStyle {
        didSet { save() }
    }

    // Model Context Protocol (MCP) Server Settings
    public var isMCPServerEnabled: Bool {
        didSet { save() }
    }
    public var mcpServerPort: Int {
        didSet { save() }
    }
    public var mcpAuthToken: String {
        didSet { save() }
    }

    // AI Assistant & Provider Settings
    public var aiProvider: AIProviderChoice {
        didSet { save() }
    }
    public var aiAPIKey: String {
        didSet { save() }
    }
    public var aiModel: String {
        didSet { save() }
    }
    public var aiCustomBaseURL: String {
        didSet { save() }
    }
    public var aiSystemPrompt: String {
        didSet { save() }
    }

    private init() {
        self.isInitializing = true

        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let cocoaDir = appSupport.appendingPathComponent("Cocoa", isDirectory: true)
        try? fileManager.createDirectory(at: cocoaDir, withIntermediateDirectories: true)
        let fileURL = cocoaDir.appendingPathComponent("settings.json")
        self.settingsFileURL = fileURL

        var loadedPayload: AppSettingsPayload? = nil
        if fileManager.fileExists(atPath: fileURL.path) {
            if let data = try? Data(contentsOf: fileURL),
               let decoded = try? JSONDecoder().decode(AppSettingsPayload.self, from: data) {
                loadedPayload = decoded
            }
        }

        let defaults = UserDefaults.standard

        // Supabase Settings (prioritize file, fallback to defaults)
        let defaultURL = defaults.string(forKey: "supabase_url") ?? ""
        self.supabaseURL = loadedPayload?.supabaseURL.isEmpty == false ? loadedPayload!.supabaseURL : defaultURL

        let defaultKey = defaults.string(forKey: "supabase_anon_key") ?? ""
        self.supabaseAnonKey = loadedPayload?.supabaseAnonKey.isEmpty == false ? loadedPayload!.supabaseAnonKey : defaultKey

        let defaultSync = defaults.bool(forKey: "cloud_sync_enabled")
        self.isCloudSyncEnabled = loadedPayload != nil ? loadedPayload!.isCloudSyncEnabled : defaultSync

        // Timer Settings
        let storedWork = defaults.integer(forKey: "pomo_work_minutes")
        let defaultWork = storedWork > 0 ? storedWork : 25
        self.pomoWorkMinutes = loadedPayload != nil ? loadedPayload!.pomoWorkMinutes : defaultWork

        let storedBreak = defaults.integer(forKey: "pomo_break_minutes")
        let defaultBreak = storedBreak > 0 ? storedBreak : 5
        self.pomoBreakMinutes = loadedPayload != nil ? loadedPayload!.pomoBreakMinutes : defaultBreak

        let storedSound = defaults.object(forKey: "sound_enabled") == nil ? true : defaults.bool(forKey: "sound_enabled")
        self.soundEnabled = loadedPayload != nil ? loadedPayload!.soundEnabled : storedSound

        let storedSuccessEnabled = defaults.object(forKey: "is_success_sound_enabled") == nil ? storedSound : defaults.bool(forKey: "is_success_sound_enabled")
        self.isSuccessSoundEnabled = loadedPayload?.isSuccessSoundEnabled ?? storedSuccessEnabled

        let storedSuccessSound = defaults.string(forKey: "success_sound") ?? "Glass"
        self.successSound = loadedPayload?.successSound.isEmpty == false ? loadedPayload!.successSound : storedSuccessSound

        let storedTaskAlertEnabled = defaults.object(forKey: "is_task_alert_sound_enabled") == nil ? true : defaults.bool(forKey: "is_task_alert_sound_enabled")
        self.isTaskAlertSoundEnabled = loadedPayload?.isTaskAlertSoundEnabled ?? storedTaskAlertEnabled

        let storedTaskAlertSound = defaults.string(forKey: "task_alert_sound") ?? "Ping"
        self.taskAlertSound = loadedPayload?.taskAlertSound.isEmpty == false ? loadedPayload!.taskAlertSound : storedTaskAlertSound

        let storedNotificationEnabled = defaults.object(forKey: "is_notification_sound_enabled") == nil ? true : defaults.bool(forKey: "is_notification_sound_enabled")
        self.isNotificationSoundEnabled = loadedPayload?.isNotificationSoundEnabled ?? storedNotificationEnabled

        let storedNotificationSound = defaults.string(forKey: "notification_sound") ?? "Tink"
        self.notificationSound = loadedPayload?.notificationSound.isEmpty == false ? loadedPayload!.notificationSound : storedNotificationSound

        // Notch Settings
        let storedHover = defaults.double(forKey: "hover_delay_seconds")
        let defaultHover = storedHover > 0 ? storedHover : 0.35
        self.hoverDelaySeconds = loadedPayload != nil ? loadedPayload!.hoverDelaySeconds : defaultHover

        let storedShield = defaults.object(forKey: "notch_shield_enabled") == nil ? true : defaults.bool(forKey: "notch_shield_enabled")
        self.isNotchShieldEnabled = loadedPayload != nil ? loadedPayload!.isNotchShieldEnabled : storedShield

        let storedStyle = defaults.string(forKey: "notch_left_style") ?? NotchLeftStyle.cocoaAndDot.rawValue
        let resolvedStyleStr = loadedPayload?.notchLeftStyle ?? storedStyle
        if resolvedStyleStr == "coconutAndDot" || resolvedStyleStr == "cocoaAndDot" {
            self.notchLeftStyle = .cocoaAndDot
        } else {
            self.notchLeftStyle = NotchLeftStyle(rawValue: resolvedStyleStr) ?? .cocoaAndDot
        }

        // MCP Settings
        let storedMCP = defaults.object(forKey: "mcp_server_enabled") == nil ? true : defaults.bool(forKey: "mcp_server_enabled")
        self.isMCPServerEnabled = loadedPayload != nil ? loadedPayload!.isMCPServerEnabled : storedMCP

        let storedPort = defaults.integer(forKey: "mcp_server_port")
        let defaultPort = storedPort > 0 ? storedPort : 4040
        self.mcpServerPort = loadedPayload != nil ? loadedPayload!.mcpServerPort : defaultPort

        self.mcpAuthToken = loadedPayload?.mcpAuthToken ?? (defaults.string(forKey: "mcp_auth_token") ?? "")

        // AI Provider Settings
        let storedProvider = defaults.string(forKey: "ai_provider") ?? AIProviderChoice.anthropic.rawValue
        let resolvedProviderStr = loadedPayload?.aiProvider ?? storedProvider
        let resolvedProvider = AIProviderChoice(rawValue: resolvedProviderStr) ?? .anthropic
        self.aiProvider = resolvedProvider

        self.aiAPIKey = loadedPayload?.aiAPIKey ?? (defaults.string(forKey: "ai_api_key") ?? "")

        let storedModel = defaults.string(forKey: "ai_model") ?? ""
        let resolvedModel = loadedPayload?.aiModel ?? storedModel
        self.aiModel = resolvedModel.isEmpty ? resolvedProvider.defaultModel : resolvedModel

        self.aiCustomBaseURL = loadedPayload?.aiCustomBaseURL ?? (defaults.string(forKey: "ai_custom_base_url") ?? "http://localhost:11434/v1")

        self.aiSystemPrompt = loadedPayload?.aiSystemPrompt ?? (defaults.string(forKey: "ai_system_prompt") ?? "You are Cocoa Focus Assistant. You help organize tasks, break down complex work into clear actionable subtasks, and estimate focus sessions.")

        self.isInitializing = false
        // Persist immediately so settings.json is guaranteed to exist on disk
        self.save()
    }

    public func save() {
        guard !isInitializing else { return }

        // 1. Persist to disk as JSON
        let payload = AppSettingsPayload(
            supabaseURL: supabaseURL,
            supabaseAnonKey: supabaseAnonKey,
            isCloudSyncEnabled: isCloudSyncEnabled,
            pomoWorkMinutes: pomoWorkMinutes,
            pomoBreakMinutes: pomoBreakMinutes,
            soundEnabled: soundEnabled,
            isSuccessSoundEnabled: isSuccessSoundEnabled,
            successSound: successSound,
            isTaskAlertSoundEnabled: isTaskAlertSoundEnabled,
            taskAlertSound: taskAlertSound,
            isNotificationSoundEnabled: isNotificationSoundEnabled,
            notificationSound: notificationSound,
            hoverDelaySeconds: hoverDelaySeconds,
            isNotchShieldEnabled: isNotchShieldEnabled,
            notchLeftStyle: notchLeftStyle.rawValue,
            isMCPServerEnabled: isMCPServerEnabled,
            mcpServerPort: mcpServerPort,
            mcpAuthToken: mcpAuthToken,
            aiProvider: aiProvider.rawValue,
            aiAPIKey: aiAPIKey,
            aiModel: aiModel,
            aiCustomBaseURL: aiCustomBaseURL,
            aiSystemPrompt: aiSystemPrompt
        )

        do {
            let data = try JSONEncoder().encode(payload)
            try data.write(to: settingsFileURL, options: [.atomic])
        } catch {
            print("[AppSettings] Failed to save settings to disk:", error)
        }

        // 2. Mirror to UserDefaults for macOS defaults compatibility
        let defaults = UserDefaults.standard
        defaults.set(supabaseURL, forKey: "supabase_url")
        defaults.set(supabaseAnonKey, forKey: "supabase_anon_key")
        defaults.set(isCloudSyncEnabled, forKey: "cloud_sync_enabled")
        defaults.set(pomoWorkMinutes, forKey: "pomo_work_minutes")
        defaults.set(pomoBreakMinutes, forKey: "pomo_break_minutes")
        defaults.set(soundEnabled, forKey: "sound_enabled")
        defaults.set(isSuccessSoundEnabled, forKey: "is_success_sound_enabled")
        defaults.set(successSound, forKey: "success_sound")
        defaults.set(isTaskAlertSoundEnabled, forKey: "is_task_alert_sound_enabled")
        defaults.set(taskAlertSound, forKey: "task_alert_sound")
        defaults.set(isNotificationSoundEnabled, forKey: "is_notification_sound_enabled")
        defaults.set(notificationSound, forKey: "notification_sound")
        defaults.set(hoverDelaySeconds, forKey: "hover_delay_seconds")
        defaults.set(isNotchShieldEnabled, forKey: "notch_shield_enabled")
        defaults.set(notchLeftStyle.rawValue, forKey: "notch_left_style")
        defaults.set(isMCPServerEnabled, forKey: "mcp_server_enabled")
        defaults.set(mcpServerPort, forKey: "mcp_server_port")
        defaults.set(mcpAuthToken, forKey: "mcp_auth_token")
        defaults.set(aiProvider.rawValue, forKey: "ai_provider")
        defaults.set(aiAPIKey, forKey: "ai_api_key")
        defaults.set(aiModel, forKey: "ai_model")
        defaults.set(aiCustomBaseURL, forKey: "ai_custom_base_url")
        defaults.set(aiSystemPrompt, forKey: "ai_system_prompt")
        defaults.synchronize()
    }

    public var isSupabaseConfigured: Bool {
        let trimmedURL = supabaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = supabaseAnonKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedURL.isEmpty && !trimmedKey.isEmpty && trimmedURL.hasPrefix("http")
    }

    public var isAIConfigured: Bool {
        if aiProvider == .ollama {
            return !aiCustomBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } else {
            return !aiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
