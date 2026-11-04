import AppKit

public struct CocoaSoundOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let emoji: String
    public let description: String

    public init(id: String, name: String, emoji: String, description: String) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.description = description
    }
}

public final class SoundManager: @unchecked Sendable {
    public static let shared = SoundManager()

    public static let availableSounds: [CocoaSoundOption] = [
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

    private init() {}

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
        if let sound = NSSound(named: name) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }
}
