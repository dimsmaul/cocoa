import AppKit
import Foundation
import Testing
@testable import CocoaApp

// These tests cover pure logic only. They must never create TaskStore or touch
// AppSettings.shared: both read the real settings file and can push to Supabase.

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.firstWeekday = 1
    return calendar
}()

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
    utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

// MARK: - Recurrence schedule (2026-11-04 is a Wednesday)

@Test func dailyMovesToTomorrow() {
    let rule = TaskRecurrence(frequency: .daily)
    let next = rule.nextDueDate(from: date(2026, 11, 4), now: date(2026, 11, 4), calendar: utc)
    #expect(next == date(2026, 11, 5))
}

@Test func overdueDailySkipsMissedDays() {
    let rule = TaskRecurrence(frequency: .daily)
    let next = rule.nextDueDate(from: date(2026, 11, 1), now: date(2026, 11, 4), calendar: utc)
    #expect(next == date(2026, 11, 5))
}

@Test func weekdaysSkipWeekend() {
    let rule = TaskRecurrence(frequency: .weekdays)
    let next = rule.nextDueDate(from: date(2026, 11, 6), now: date(2026, 11, 6), calendar: utc)
    #expect(next == date(2026, 11, 9))
}

@Test func customIntervalIsApplied() {
    let rule = TaskRecurrence(frequency: .weekly, interval: 2)
    let next = rule.nextDueDate(from: date(2026, 11, 4), now: date(2026, 11, 4), calendar: utc)
    #expect(next == date(2026, 11, 18))
}

@Test func monthlyClampsToShorterMonth() {
    let rule = TaskRecurrence(frequency: .monthly)
    let next = rule.nextDueDate(from: date(2026, 1, 31), now: date(2026, 1, 31), calendar: utc)
    #expect(next == date(2026, 2, 28))
}

@Test func completingEarlyKeepsTheSchedule() {
    let rule = TaskRecurrence(frequency: .weekly)
    let next = rule.nextDueDate(from: date(2026, 11, 9), now: date(2026, 11, 4), calendar: utc)
    #expect(next == date(2026, 11, 16))
}

@Test func missingDueDateStartsFromNow() {
    let rule = TaskRecurrence(frequency: .daily)
    let next = rule.nextDueDate(from: nil, now: date(2026, 11, 4), calendar: utc)
    #expect(next == date(2026, 11, 5))
}

@Test func nonPositiveIntervalStillAdvances() {
    let rule = TaskRecurrence(frequency: .daily, interval: 0)
    let next = rule.nextDueDate(from: date(2026, 11, 4), now: date(2026, 11, 4), calendar: utc)
    #expect(next == date(2026, 11, 5))
}

// MARK: - Recurring hand-off

private func recurringTask(due: Date = date(2026, 11, 4), reminder: Date? = nil) -> TaskItem {
    TaskItem(
        title: "Review inbox",
        notes: "notes",
        estimatedMinutes: 15,
        timeSpentSeconds: 120,
        isCompleted: true,
        priority: .high,
        listName: "Work",
        subtasks: [SubtaskItem(title: "Parent", isCompleted: true, subtasks: [SubtaskItem(title: "Child", isCompleted: true)])],
        comments: [TaskComment(content: "old comment")],
        completedAt: date(2026, 11, 4),
        board: .done,
        dueDate: due,
        recurrence: TaskRecurrence(frequency: .daily),
        reminderAt: reminder
    )
}

@Test func handOffCreatesFreshNextOccurrence() throws {
    let original = recurringTask()
    var tasks = [original]

    let next = try #require(RecurringTasks.handOff(tasks: &tasks, completedId: original.id, now: date(2026, 11, 4), calendar: utc))

    #expect(tasks.map(\.id) == [original.id, next.id])
    #expect(next.id != original.id)
    #expect(next.title == "Review inbox" && next.notes == "notes" && next.listName == "Work")
    #expect(next.estimatedMinutes == 15 && next.priority == .high)
    #expect(next.timeSpentSeconds == 0 && !next.isCompleted && next.completedAt == nil)
    #expect(next.board == .upcoming && next.dueDate == date(2026, 11, 5))
    #expect(next.recurrence == TaskRecurrence(frequency: .daily))
    #expect(next.comments.isEmpty)
    #expect(next.subtasks[0].id != original.subtasks[0].id && !next.subtasks[0].isCompleted)
    #expect(next.subtasks[0].subtasks[0].id != original.subtasks[0].subtasks[0].id && !next.subtasks[0].subtasks[0].isCompleted)
    #expect(tasks[0].recurrence == nil && tasks[0].spawnedOccurrenceId == next.id)
}

@Test func handOffIgnoresNonRecurringTask() {
    let plain = TaskItem(title: "One-off")
    var tasks = [plain]
    #expect(RecurringTasks.handOff(tasks: &tasks, completedId: plain.id, now: date(2026, 11, 4), calendar: utc) == nil)
    #expect(tasks == [plain])
}

@Test func handOffShiftsReminderWithDueDate() throws {
    let original = recurringTask(reminder: date(2026, 11, 4, 8))
    var tasks = [original]
    let next = try #require(RecurringTasks.handOff(tasks: &tasks, completedId: original.id, now: date(2026, 11, 4), calendar: utc))
    #expect(next.reminderAt == date(2026, 11, 5, 8))
}

@Test func handOffDropsReminderThatWouldBeInThePast() throws {
    let original = recurringTask(due: date(2026, 11, 10), reminder: date(2026, 11, 1))
    var tasks = [original]
    let next = try #require(RecurringTasks.handOff(tasks: &tasks, completedId: original.id, now: date(2026, 11, 20), calendar: utc))
    #expect(next.dueDate == date(2026, 11, 21))
    #expect(next.reminderAt == nil)
}

@Test func reopeningUndoesUntouchedHandOff() throws {
    let original = recurringTask()
    var tasks = [original]
    let next = try #require(RecurringTasks.handOff(tasks: &tasks, completedId: original.id, now: date(2026, 11, 4), calendar: utc))

    let removable = RecurringTasks.reopen(tasks: &tasks, reopenedId: original.id)

    #expect(removable == next.id)
    #expect(tasks[0].recurrence == TaskRecurrence(frequency: .daily))
    #expect(tasks[0].spawnedOccurrenceId == nil)
}

@Test func reopeningKeepsNextOccurrenceAlreadyStarted() throws {
    let original = recurringTask()
    var tasks = [original]
    _ = try #require(RecurringTasks.handOff(tasks: &tasks, completedId: original.id, now: date(2026, 11, 4), calendar: utc))
    tasks[1].timeSpentSeconds = 30

    let removable = RecurringTasks.reopen(tasks: &tasks, reopenedId: original.id)

    #expect(removable == nil)
    #expect(tasks[0].recurrence == nil && tasks[0].spawnedOccurrenceId == nil)
    #expect(tasks[1].recurrence != nil)
}

@Test func rollOverMovesOnlyDueUpcomingTasks() {
    var tasks = [
        TaskItem(title: "due today", board: .upcoming, dueDate: date(2026, 11, 4, 0)),
        TaskItem(title: "overdue", board: .upcoming, dueDate: date(2026, 11, 2)),
        TaskItem(title: "future", board: .upcoming, dueDate: date(2026, 11, 5)),
        TaskItem(title: "backlog", board: .backlog, dueDate: date(2026, 11, 1)),
    ]

    let changed = RecurringTasks.rollOverDueTasks(&tasks, now: date(2026, 11, 4), calendar: utc)

    #expect(changed)
    #expect(tasks.map(\.board) == [.today, .today, .upcoming, .backlog])
    #expect(!RecurringTasks.rollOverDueTasks(&tasks, now: date(2026, 11, 4), calendar: utc))
}

// MARK: - Reminders

@Test func pendingRemindersExcludeCompletedPastAndUnset() {
    let future = TaskItem(title: "future", reminderAt: date(2026, 11, 5))
    let tasks = [
        future,
        TaskItem(title: "past", reminderAt: date(2026, 11, 3)),
        TaskItem(title: "unset"),
        TaskItem(title: "done", isCompleted: true, reminderAt: date(2026, 11, 5)),
    ]
    let pending = ReminderPlan.pending(tasks: tasks, now: date(2026, 11, 4))
    #expect(pending == [future.id: PendingReminder(id: future.id, title: "future", fireDate: date(2026, 11, 5))])
}

@Test func reminderDiffOnlyTouchesWhatChanged() {
    let kept = PendingReminder(id: UUID(), title: "kept", fireDate: date(2026, 11, 5))
    let moved = PendingReminder(id: UUID(), title: "moved", fireDate: date(2026, 11, 5))
    let movedLater = PendingReminder(id: moved.id, title: "moved", fireDate: date(2026, 11, 6))
    let gone = PendingReminder(id: UUID(), title: "gone", fireDate: date(2026, 11, 5))
    let added = PendingReminder(id: UUID(), title: "added", fireDate: date(2026, 11, 7))

    let diff = ReminderPlan.diff(
        from: [kept.id: kept, moved.id: moved, gone.id: gone],
        to: [kept.id: kept, moved.id: movedLater, added.id: added]
    )

    #expect(Set(diff.removedIds) == [moved.id, gone.id])
    #expect(Set(diff.added.map(\.id)) == [moved.id, added.id])
    #expect(diff.added.first { $0.id == moved.id }?.fireDate == date(2026, 11, 6))
}

// MARK: - Focus sessions

@Test func trackerAccumulatesUntilFinished() {
    var tracker = FocusSessionTracker()
    let id = UUID()

    #expect(tracker.tick(taskId: id, taskTitle: "A", now: date(2026, 11, 4)) == nil)
    #expect(tracker.tick(taskId: id, taskTitle: "A", now: date(2026, 11, 4)) == nil)
    #expect(tracker.current?.seconds == 2)

    let finished = tracker.finish()
    #expect(finished?.taskId == id && finished?.seconds == 2 && finished?.startedAt == date(2026, 11, 4))
    #expect(tracker.current == nil)
    #expect(tracker.finish() == nil)
}

@Test func trackerSplitsSessionWhenTaskChanges() {
    var tracker = FocusSessionTracker()
    let first = UUID()
    let second = UUID()

    _ = tracker.tick(taskId: first, taskTitle: "A", now: date(2026, 11, 4))
    let finished = tracker.tick(taskId: second, taskTitle: "B", now: date(2026, 11, 4, 10))

    #expect(finished?.taskId == first && finished?.seconds == 1)
    #expect(tracker.current?.taskId == second && tracker.current?.seconds == 1)
}

private func session(_ start: Date, _ seconds: Int) -> FocusSession {
    FocusSession(taskId: UUID(), taskTitle: "t", startedAt: start, seconds: seconds)
}

@Test func lastSevenDaysIncludesEmptyDaysOldestFirst() {
    let sessions = [
        session(date(2026, 11, 4), 60),
        session(date(2026, 11, 4, 15), 30),
        session(date(2026, 11, 1), 120),
        session(date(2026, 10, 28), 999),
    ]
    let days = FocusStats.lastSevenDays(sessions: sessions, now: date(2026, 11, 4), calendar: utc)

    #expect(days.count == 7)
    #expect(days.first?.day == utc.startOfDay(for: date(2026, 10, 29)))
    #expect(days.last?.day == utc.startOfDay(for: date(2026, 11, 4)))
    #expect(days.last?.seconds == 90)
    #expect(days.map(\.seconds) == [0, 0, 0, 120, 0, 0, 90])
}

@Test func totalsForTodayAndThisWeek() {
    let sessions = [
        session(date(2026, 11, 4), 60),
        session(date(2026, 11, 1), 120),
        session(date(2026, 10, 31), 500),
    ]
    #expect(FocusStats.secondsToday(sessions: sessions, now: date(2026, 11, 4), calendar: utc) == 60)
    #expect(FocusStats.secondsThisWeek(sessions: sessions, now: date(2026, 11, 4), calendar: utc) == 180)
}

@Test func estimateVersusActualUsesRecentlyCompletedTasksNewestFirst() {
    let older = TaskItem(title: "older", estimatedMinutes: 10, timeSpentSeconds: 900, isCompleted: true, completedAt: date(2026, 11, 1))
    let newest = TaskItem(title: "newest", estimatedMinutes: 25, timeSpentSeconds: 600, isCompleted: true, completedAt: date(2026, 11, 4))
    let tooOld = TaskItem(title: "too old", isCompleted: true, completedAt: date(2026, 10, 20))
    let open = TaskItem(title: "open", timeSpentSeconds: 60)

    let rows = FocusStats.estimateVsActual(tasks: [older, newest, tooOld, open], now: date(2026, 11, 4), calendar: utc)

    #expect(rows.map(\.title) == ["newest", "older"])
    #expect(rows[0].estimatedSeconds == 1500 && rows[0].actualSeconds == 600)
}

@Test func durationsAreFormattedForReading() {
    #expect(FocusStats.formatted(seconds: 45) == "45s")
    #expect(FocusStats.formatted(seconds: 25 * 60) == "25m")
    #expect(FocusStats.formatted(seconds: 3600) == "1h")
    #expect(FocusStats.formatted(seconds: 5100) == "1h 25m")
}

@Test func sessionLogAppendsAndSkipsDamagedLines() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("focus_sessions.jsonl")
    let log = FocusSessionLog(url: url)
    #expect(log.load().isEmpty)

    let first = session(date(2026, 11, 4), 60)
    let second = session(date(2026, 11, 4, 10), 30)
    try log.append(first)
    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("{damaged\n".utf8))
    try handle.close()
    try log.append(second)

    #expect(log.load() == [first, second])
}

// MARK: - Saved data compatibility

@Test func oldTasksFileStillDecodes() throws {
    let json = #"[{"id":"7D0F6A11-6C1B-4E2D-9C1A-1F0E2D3C4B5A","title":"Old task"}]"#
    let tasks = try JSONDecoder().decode([TaskItem].self, from: Data(json.utf8))
    #expect(tasks[0].title == "Old task")
    #expect(tasks[0].recurrence == nil && tasks[0].reminderAt == nil && tasks[0].spawnedOccurrenceId == nil)
}

@Test func newTaskFieldsSurviveSaving() throws {
    let original = TaskItem(
        title: "Saved",
        recurrence: TaskRecurrence(frequency: .weekly, interval: 2),
        reminderAt: date(2026, 11, 5),
        spawnedOccurrenceId: UUID()
    )
    let decoded = try JSONDecoder().decode(TaskItem.self, from: JSONEncoder().encode(original))
    #expect(decoded.recurrence == original.recurrence)
    #expect(decoded.reminderAt == original.reminderAt)
    #expect(decoded.spawnedOccurrenceId == original.spawnedOccurrenceId)
}

@Test func oldSettingsFileGetsDefaultQuickCaptureShortcut() throws {
    let payload = try JSONDecoder().decode(AppSettingsPayload.self, from: Data("{}".utf8))
    #expect(payload.isQuickCaptureEnabled)
    #expect(payload.quickCaptureShortcut == .defaultQuickCapture)
}

// MARK: - Hotkey

@Test func defaultShortcutDisplay() {
    #expect(HotkeyShortcut.defaultQuickCapture.displayString == "⌃⌥N")
}

@Test func shortcutRecordsAllModifiersInDisplayOrder() throws {
    let shortcut = try #require(HotkeyShortcut(keyCode: 40, modifierFlags: [.command, .shift, .option, .control], characters: "k"))
    #expect(shortcut.keyCode == 40)
    #expect(shortcut.displayString == "⌃⌥⇧⌘K")
}

@Test func shortcutNeedsARealModifier() {
    #expect(HotkeyShortcut(keyCode: 40, modifierFlags: [], characters: "k") == nil)
    #expect(HotkeyShortcut(keyCode: 40, modifierFlags: [.shift], characters: "k") == nil)
}

@Test func shortcutNamesSpecialKeys() throws {
    let space = try #require(HotkeyShortcut(keyCode: 49, modifierFlags: [.option], characters: " "))
    #expect(space.displayString == "⌥Space")
    let arrow = try #require(HotkeyShortcut(keyCode: 126, modifierFlags: [.command], characters: "\u{F700}"))
    #expect(arrow.displayString == "⌘↑")
}

// MARK: - Inbox

@Test(arguments: [TaskBoard.inbox, .today, .upcoming])
func inboxShowsOpenTasksFromActiveBoards(board: TaskBoard) {
    #expect(TaskItem(title: "t", board: board).isInInbox)
}

@Test func inboxLeavesBacklogToItsOwnMenu() {
    #expect(!TaskItem(title: "t", board: .backlog).isInInbox)
}

@Test func inboxHidesCompletedTasks() {
    #expect(!TaskItem(title: "t", isCompleted: true, board: .done).isInInbox)
    #expect(!TaskItem(title: "t", isCompleted: true, board: .today).isInInbox)
}

@Test func quickCaptureTaskIsVisibleInInbox() throws {
    #expect(try #require(TaskItem.quickCapture(title: "idea")).isInInbox)
}

// MARK: - Today group

@Test(arguments: [TaskBoard.inbox, .today])
func taskWithoutDateIsInTodayGroup(board: TaskBoard) {
    let task = TaskItem(title: "t", board: board, dueDate: nil)
    var undated = task
    undated.dueDate = nil
    #expect(undated.isInTodayGroup(now: date(2026, 11, 4), calendar: utc))
}

@Test func taskDueTodayIsInTodayGroupWhateverItsBoard() {
    let task = TaskItem(title: "t", board: .upcoming, dueDate: date(2026, 11, 4, 18))
    #expect(task.isInTodayGroup(now: date(2026, 11, 4), calendar: utc))
}

@Test func overdueAndFutureTasksAreNotInTodayGroup() {
    #expect(!TaskItem(title: "t", board: .today, dueDate: date(2026, 11, 3)).isInTodayGroup(now: date(2026, 11, 4), calendar: utc))
    #expect(!TaskItem(title: "t", board: .upcoming, dueDate: date(2026, 11, 5)).isInTodayGroup(now: date(2026, 11, 4), calendar: utc))
}

@Test func backlogAndCompletedTasksAreNotInTodayGroup() {
    #expect(!TaskItem(title: "t", board: .backlog, dueDate: date(2026, 11, 4)).isInTodayGroup(now: date(2026, 11, 4), calendar: utc))
    #expect(!TaskItem(title: "t", isCompleted: true, board: .done, dueDate: date(2026, 11, 4)).isInTodayGroup(now: date(2026, 11, 4), calendar: utc))
}

@Test func quickCaptureTaskIsInTodayGroup() throws {
    let task = try #require(TaskItem.quickCapture(title: "idea"))
    #expect(task.isInTodayGroup(now: date(2026, 11, 4), calendar: utc))
}

// MARK: - MCP request guard

private func head(_ headers: String...) -> String {
    (["POST /mcp HTTP/1.1"] + headers).joined(separator: "\r\n")
}

@Test(arguments: ["127.0.0.1:4040", "localhost:4040", "LOCALHOST", "[::1]:4040"])
func localHostHeaderIsAllowed(host: String) {
    #expect(HTTPRequestGuard.rejectionStatus(forRequestHead: head("Host: \(host)"), authToken: "") == nil)
}

@Test(arguments: ["evil.example", "evil.example:4040", "192.168.1.5:4040", "localhost.evil.example"])
func otherHostHeaderIsRejectedToStopDNSRebinding(host: String) {
    #expect(HTTPRequestGuard.rejectionStatus(forRequestHead: head("Host: \(host)"), authToken: "") == 403)
}

@Test func missingHostHeaderIsRejected() {
    #expect(HTTPRequestGuard.rejectionStatus(forRequestHead: head("Content-Length: 2"), authToken: "") == 403)
}

@Test(arguments: ["https://evil.example", "null", "http://localhost:3000"])
func requestFromABrowserIsRejected(origin: String) {
    let request = head("Host: 127.0.0.1:4040", "Origin: \(origin)")
    #expect(HTTPRequestGuard.rejectionStatus(forRequestHead: request, authToken: "") == 403)
}

@Test func headerNamesAreCaseInsensitive() {
    let request = head("HOST: 127.0.0.1:4040", "oRiGiN: https://evil.example")
    #expect(HTTPRequestGuard.rejectionStatus(forRequestHead: request, authToken: "") == 403)
}

@Test func tokenIsRequiredOnceConfigured() {
    let local = "Host: 127.0.0.1:4040"
    #expect(HTTPRequestGuard.rejectionStatus(forRequestHead: head(local), authToken: "secret") == 401)
    #expect(HTTPRequestGuard.rejectionStatus(forRequestHead: head(local, "Authorization: Bearer wrong"), authToken: "secret") == 401)
    #expect(HTTPRequestGuard.rejectionStatus(forRequestHead: head(local, "Authorization: Bearer secret"), authToken: "secret") == nil)
}

@Test func blankTokenMeansNoTokenCheck() {
    #expect(HTTPRequestGuard.rejectionStatus(forRequestHead: head("Host: localhost"), authToken: "   ") == nil)
}

// MARK: - Tower carousel

private let carouselOrder = [UUID(), UUID(), UUID()]

@Test func movingDownTheListSlidesForward() {
    #expect(FocusCarousel.slidesForward(from: carouselOrder[0], to: carouselOrder[2], in: carouselOrder))
}

@Test func movingUpTheListSlidesBackward() {
    #expect(!FocusCarousel.slidesForward(from: carouselOrder[2], to: carouselOrder[1], in: carouselOrder))
}

@Test func taskMissingFromTheListSlidesForward() {
    #expect(FocusCarousel.slidesForward(from: nil, to: carouselOrder[0], in: carouselOrder))
    #expect(FocusCarousel.slidesForward(from: UUID(), to: carouselOrder[0], in: carouselOrder))
    #expect(FocusCarousel.slidesForward(from: carouselOrder[1], to: nil, in: carouselOrder))
}

// MARK: - Quick capture

@Test func quickCaptureTrimsAndGoesToInbox() throws {
    let task = try #require(TaskItem.quickCapture(title: "  Call dentist \n"))
    #expect(task.title == "Call dentist")
    #expect(task.board == .inbox && task.listName == "General" && task.dueDate == nil)
}

@Test func quickCaptureRejectsBlankTitle() {
    #expect(TaskItem.quickCapture(title: "   \n") == nil)
}
