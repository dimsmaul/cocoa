import Foundation
import Observation
import UserNotifications

/// Keeps macOS notifications in step with each task's `reminderAt`.
@MainActor
@Observable
public final class ReminderService: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = ReminderService()

    public private(set) var isDenied = false
    public var onOpenTask: ((UUID) -> Void)?

    private var scheduled: [UUID: PendingReminder] = [:]

    /// UNUserNotificationCenter crashes in a process without a bundle identifier, such as `swift run`.
    public var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    public func start(tasks: [TaskItem]) {
        guard isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // Rebuilt below, which also clears notifications for tasks changed while Cocoa was closed.
        center.removeAllPendingNotificationRequests()
        scheduled = [:]
        sync(tasks: tasks)
    }

    /// Cheap enough to run on every save: it only touches macOS when a reminder actually changed.
    public func sync(tasks: [TaskItem]) {
        guard isAvailable else { return }
        let desired = ReminderPlan.pending(tasks: tasks, now: Date())
        let diff = ReminderPlan.diff(from: scheduled, to: desired)
        guard !diff.added.isEmpty || !diff.removedIds.isEmpty else { return }
        scheduled = desired

        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: diff.removedIds.map(identifier))
        guard !diff.added.isEmpty else { return }

        Task {
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                isDenied = !granted
                guard granted else { return }
                for reminder in diff.added {
                    try await UNUserNotificationCenter.current().add(request(for: reminder))
                }
            } catch {
                isDenied = true
                print("[ReminderService] Could not schedule reminder:", error.localizedDescription)
            }
        }
    }

    private func identifier(for id: UUID) -> String {
        "cocoa.reminder.\(id.uuidString)"
    }

    private func request(for reminder: PendingReminder) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = "Cocoa reminder"
        content.sound = AppSettings.shared.isNotificationSoundEnabled ? .default : nil
        content.userInfo = ["taskId": reminder.id.uuidString]

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: identifier(for: reminder.id), content: content, trigger: trigger)
    }

    // Without this, macOS hides notifications while Cocoa is the frontmost app.
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let taskId = (response.notification.request.content.userInfo["taskId"] as? String).flatMap(UUID.init(uuidString:))
        completionHandler()
        Task { @MainActor in
            if let taskId {
                ReminderService.shared.onOpenTask?(taskId)
            }
        }
    }
}
