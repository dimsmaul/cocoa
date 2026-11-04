import AppKit
import UniformTypeIdentifiers

public struct CocoaSoundOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let emoji: String
    public let description: String
    public let isCustom: Bool

    public init(id: String, name: String, emoji: String, description: String, isCustom: Bool = false) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.description = description
        self.isCustom = isCustom
    }
}

@Observable
public final class SoundManager: @unchecked Sendable {
    public static let shared = SoundManager()

    public static let systemSounds: [CocoaSoundOption] = [
        CocoaSoundOption(id: "Glass", name: "Glass", emoji: "🥂", description: "Bright crystal chime"),
        CocoaSoundOption(id: "Hero", name: "Hero", emoji: "🎺", description: "Triumphant fanfare"),
        CocoaSoundOption(id: "Ping", name: "Ping", emoji: "🔔", description: "Clean sharp bell"),
        CocoaSoundOption(id: "Pop", name: "Pop", emoji: "🫧", description: "Subtle bubble pop"),
        CocoaSoundOption(id: "Purr", name: "Purr", emoji: "🐱", description: "Soft gentle vibration"),
        CocoaSoundOption(id: "Tink", name: "Tink", emoji: "🥢", description: "Light crisp strike"),
        CocoaSoundOption(id: "Bottle", name: "Bottle", emoji: "🍾", description: "Mellow bottle tap"),
        CocoaSoundOption(id: "Blow", name: "Blow", emoji: "💨", description: "Warm gentle whoosh"),
        CocoaSoundOption(id: "Funk", name: "Funk", emoji: "🎸", description: "Playful funk riff"),
        CocoaSoundOption(id: "Submarine", name: "Submarine", emoji: "🌊", description: "Sonar radar pulse"),
        CocoaSoundOption(id: "Morse", name: "Morse", emoji: "📻", description: "Classic telegraph pip"),
        CocoaSoundOption(id: "Sosumi", name: "Sosumi", emoji: "🎵", description: "Vintage Mac chime"),
        CocoaSoundOption(id: "Basso", name: "Basso", emoji: "🥁", description: "Deep resonant thud"),
        CocoaSoundOption(id: "Frog", name: "Frog", emoji: "🐸", description: "Quirky low ribbit")
    ]

    public var customSounds: [CocoaSoundOption] = []

    public var allAvailableSounds: [CocoaSoundOption] {
        return customSounds + Self.systemSounds
    }

    public static var availableSounds: [CocoaSoundOption] {
        return SoundManager.shared.allAvailableSounds
    }

    /// Local folder where user custom sound files are stored on this Mac
    public var customSoundsDirectory: URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Cocoa/Sounds", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var currentSound: NSSound?

    private init() {
        reloadCustomSounds()
    }

    /// Scan ~/Library/Application Support/Cocoa/Sounds for local audio files
    public func reloadCustomSounds() {
        let fileManager = FileManager.default
        let dir = customSoundsDirectory
        guard let files = try? fileManager.contentsOfDirectory(atPath: dir.path) else {
            customSounds = []
            return
        }

        let validExtensions: Set<String> = ["mp3", "wav", "m4a", "aiff", "aif", "caf", "aac", "ogg"]
        var loaded: [CocoaSoundOption] = []

        for fileName in files.sorted() {
            guard !fileName.hasPrefix(".") else { continue }
            let ext = (fileName as NSString).pathExtension.lowercased()
            guard validExtensions.contains(ext) else { continue }

            let baseName = (fileName as NSString).deletingPathExtension
            loaded.append(
                CocoaSoundOption(
                    id: "custom:\(fileName)",
                    name: baseName,
                    emoji: "🎵",
                    description: "Custom local audio (\(ext.uppercased()))",
                    isCustom: true
                )
            )
        }

        self.customSounds = loaded
    }

    /// Import an audio file from anywhere on disk into local Cocoa/Sounds directory
    @discardableResult
    public func importCustomSound(from sourceURL: URL) throws -> CocoaSoundOption {
        let fileManager = FileManager.default
        let fileName = sourceURL.lastPathComponent
        let destURL = customSoundsDirectory.appendingPathComponent(fileName)

        if fileManager.fileExists(atPath: destURL.path) {
            try? fileManager.removeItem(at: destURL)
        }

        try fileManager.copyItem(at: sourceURL, to: destURL)
        reloadCustomSounds()

        let baseName = (fileName as NSString).deletingPathExtension
        let ext = sourceURL.pathExtension.lowercased()
        return CocoaSoundOption(
            id: "custom:\(fileName)",
            name: baseName,
            emoji: "🎵",
            description: "Custom local audio (\(ext.uppercased()))",
            isCustom: true
        )
    }

    /// Delete a custom local sound file
    public func deleteCustomSound(id: String) {
        let fileName = id.hasPrefix("custom:") ? String(id.dropFirst(7)) : id
        let fileURL = customSoundsDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)
        reloadCustomSounds()

        // Fallback to defaults if active setting used this deleted sound
        let settings = AppSettings.shared
        if settings.successSound == id || settings.successSound == fileName {
            settings.successSound = "Glass"
        }
        if settings.taskAlertSound == id || settings.taskAlertSound == fileName {
            settings.taskAlertSound = "Ping"
        }
        if settings.notificationSound == id || settings.notificationSound == fileName {
            settings.notificationSound = "Tink"
        }
    }

    /// Open local Sounds directory in Finder
    public func revealCustomSoundsInFinder() {
        let dir = customSoundsDirectory
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir.path)
    }

    /// Prompt user with file open picker to select an audio file
    public func promptImportCustomSound(completion: @escaping (CocoaSoundOption?) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Import Custom Audio File"
        panel.prompt = "Import Sound"
        panel.message = "Choose an audio file (.mp3, .wav, .m4a, .aiff) to use as a Cocoa sound effect:"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType.audio,
            UTType.mp3,
            UTType.wav,
            UTType.aiff,
            UTType.mpeg4Audio
        ].compactMap { $0 }

        panel.begin { response in
            if response == .OK, let selectedURL = panel.url {
                do {
                    let option = try self.importCustomSound(from: selectedURL)
                    DispatchQueue.main.async {
                        completion(option)
                    }
                } catch {
                    print("[SoundManager] Failed to import audio:", error)
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                }
            } else {
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }

    /// Played when a task is completed or a Pomodoro session successfully finishes
    public func playSuccessSound() {
        let settings = AppSettings.shared
        guard settings.soundEnabled && settings.isSuccessSoundEnabled else { return }
        playNamedSound(settings.successSound)
    }

    public func playCompletionSound() {
        playSuccessSound()
    }

    /// Played during active tasks, Pomodoro midway alert, or timer state reminders
    public func playTaskAlertSound() {
        let settings = AppSettings.shared
        guard settings.soundEnabled && settings.isTaskAlertSoundEnabled else { return }
        playNamedSound(settings.taskAlertSound)
    }

    public func playAlertSound() {
        playTaskAlertSound()
    }

    /// Played for system notifications, AI assistant updates, or sync alerts
    public func playNotificationSound() {
        let settings = AppSettings.shared
        guard settings.soundEnabled && settings.isNotificationSoundEnabled else { return }
        playNamedSound(settings.notificationSound)
    }

    public func playTickSound() {
        guard AppSettings.shared.soundEnabled else { return }
        if let sound = NSSound(named: "Tink") {
            sound.volume = 0.2
            sound.play()
        }
    }

    public func playNamedSound(_ name: String) {
        // 1. Check custom local sound files
        let cleanName = name.hasPrefix("custom:") ? String(name.dropFirst(7)) : name
        let customURL = customSoundsDirectory.appendingPathComponent(cleanName)
        if FileManager.default.fileExists(atPath: customURL.path),
           let sound = NSSound(contentsOf: customURL, byReference: true) {
            self.currentSound = sound
            sound.play()
            return
        }

        // Search by basename in custom sounds directory
        if let matchedFile = (try? FileManager.default.contentsOfDirectory(atPath: customSoundsDirectory.path))?
            .first(where: { ($0 as NSString).deletingPathExtension == cleanName || $0 == cleanName }) {
            let matchedURL = customSoundsDirectory.appendingPathComponent(matchedFile)
            if let sound = NSSound(contentsOf: matchedURL, byReference: true) {
                self.currentSound = sound
                sound.play()
                return
            }
        }

        // 2. Built-in macOS system sound
        if let sound = NSSound(named: name) {
            self.currentSound = sound
            sound.play()
            return
        }

        // 3. Fallback beep
        NSSound.beep()
    }
}
