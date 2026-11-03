import Foundation
import Observation
import Combine

public enum TimerState: String, Sendable {
    case idle
    case running
    case paused
    case completed
}

@Observable
public final class TimerManager: @unchecked Sendable {
    public var state: TimerState = .idle
    public var remainingSeconds: Int = 25 * 60
    public var totalSeconds: Int = 25 * 60
    public var isBreak: Bool = false

    private var timerCancellable: AnyCancellable?
    private weak var taskStore: TaskStore?

    public init(taskStore: TaskStore? = nil) {
        self.taskStore = taskStore
        syncWithActiveTask()
    }

    public func setTaskStore(_ store: TaskStore) {
        self.taskStore = store
        syncWithActiveTask()
    }

    public var isRunning: Bool {
        return state == .running
    }

    public var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        let spent = totalSeconds - remainingSeconds
        return min(1.0, max(0.0, Double(spent) / Double(totalSeconds)))
    }

    public var formattedTime: String {
        let mins = remainingSeconds / 60
        let secs = remainingSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    public func syncWithActiveTask() {
        guard state == .idle else { return }
        if let active = taskStore?.activeTask {
            let remaining = max(0, active.estimatedSeconds - active.timeSpentSeconds)
            self.totalSeconds = active.estimatedSeconds
            self.remainingSeconds = remaining > 0 ? remaining : active.estimatedSeconds
        } else {
            self.totalSeconds = 25 * 60
            self.remainingSeconds = 25 * 60
        }
    }

    public func start() {
        guard state != .running else { return }
        state = .running
        startTicker()
    }

    public func pause() {
        guard state == .running else { return }
        state = .paused
        stopTicker()
    }

    public func toggle() {
        if state == .running {
            pause()
        } else {
            start()
        }
    }

    public func reset() {
        stopTicker()
        state = .idle
        syncWithActiveTask()
    }

    public func completeCurrentSession() {
        stopTicker()
        state = .completed
        SoundManager.shared.playCompletionSound()

        if let active = taskStore?.activeTask {
            taskStore?.toggleCompleted(id: active.id)
        }

        // Reset for next task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            self.state = .idle
            self.syncWithActiveTask()
        }
    }

    private func startTicker() {
        stopTicker()
        timerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    private func stopTicker() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    private func tick() {
        guard state == .running else { return }

        if remainingSeconds > 0 {
            remainingSeconds -= 1

            // Record 1 second progress on the active task
            if let activeId = taskStore?.activeTaskId {
                taskStore?.recordTimeSpent(id: activeId, seconds: 1)
            }
        } else {
            // Timer expired!
            completeCurrentSession()
        }
    }
}
