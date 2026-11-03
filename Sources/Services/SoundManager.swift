import AppKit

public final class SoundManager: @unchecked Sendable {
    public static let shared = SoundManager()

    private init() {}

    public func playCompletionSound() {
        if let sound = NSSound(named: "Glass") {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    public func playTickSound() {
        if let sound = NSSound(named: "Tink") {
            sound.volume = 0.2
            sound.play()
        }
    }

    public func playAlertSound() {
        if let sound = NSSound(named: "Ping") {
            sound.play()
        } else {
            NSSound.beep()
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
