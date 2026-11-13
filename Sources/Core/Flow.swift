import Foundation

enum Outcome: String, Codable { case completed, failed, carried, deleted }
enum FlowRepeat: String, Codable, CaseIterable, Identifiable {
    case daily, weekdays, weekly, monthly
    var id: String { rawValue }
    var label: String {
        switch self { case .daily: return "毎日"; case .weekdays: return "平日"; case .weekly: return "毎週"; case .monthly: return "毎月" }
    }
}
struct FlowTask: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var note = ""
    var day: Date
    var favorite = false
    var originDay: Date? = nil
    // Optional fields keep v0.1-v0.3 JSON readable without a migration.
    var repeatRule: FlowRepeat? = nil
    var repeatAnchorDay: Int? = nil
    var repeatAnchorWeekday: Int? = nil
    var priority: FlowPriority? = nil
    var category: String? = nil
    var subtasks: [FlowSubtask]? = nil
    var goalStepID: UUID? = nil
    var habitGoal: Int? = nil
    var muteReminder: Bool? = nil
}
struct FlowCompletionUndo: Codable {
    let original: FlowTask
    let next: FlowTask?
    let habitRecord: FlowHabitRecord?
}

struct FlowEvent: Identifiable, Codable {
    var id = UUID()
    var taskID: UUID
    var title: String
    var day: Date
    var recordedAt: Date
    var outcome: Outcome
    var category: String? = nil
    var subtasks: [FlowSubtask]? = nil
    var favorite: Bool? = nil
    var completionUndo: FlowCompletionUndo? = nil
}
struct FlowData: Codable {
    static let currentSchema = 5
    var schemaVersion = FlowData.currentSchema
    var tasks: [FlowTask] = []
    var history: [FlowEvent] = []
    var categoryButtons: [String]? = nil
    var goals: [FlowGoal]? = nil
    var habitRecords: [FlowHabitRecord]? = nil
    func validated() throws -> FlowData {
        guard (1...Self.currentSchema).contains(schemaVersion), Set(tasks.map(\.id)).count == tasks.count,
              Set(history.map(\.id)).count == history.count,
              tasks.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.title.count <= 1000 && $0.note.count <= 20000 && ($0.repeatAnchorDay.map { (1...31).contains($0) } ?? true) && ($0.repeatAnchorWeekday.map { (1...7).contains($0) } ?? true) })
        else { throw FlowError.invalidBackup }
        func validItems(_ items: [FlowSubtask]?) -> Bool {
            let items = items ?? []
            return items.count <= 50 && Set(items.map(\.id)).count == items.count && items.allSatisfy {
                !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.title.count <= 200
            }
        }
        guard tasks.allSatisfy({ validItems($0.subtasks) && (FlowCategories.normalized($0.category)?.count ?? 0) <= 40 }),
              history.allSatisfy({ validItems($0.subtasks) && (FlowCategories.normalized($0.category)?.count ?? 0) <= 40 }) else { throw FlowError.invalidBackup }
        guard Set(annualGoals.map(\.id)).count == annualGoals.count,
              annualGoals.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.title.count <= 1000 && validItems($0.steps) }),
              tasks.allSatisfy({ $0.habitGoal.map { (1...7).contains($0) } ?? true }),
              Set(habitDays.map(\.key)).count == habitDays.count else { throw FlowError.invalidBackup }
        let goalStepIDs = annualGoals.flatMap { $0.steps.map(\.id) }
        guard Set(goalStepIDs).count == goalStepIDs.count else { throw FlowError.invalidBackup }
        var upgraded = self
        upgraded.schemaVersion = Self.currentSchema
        for i in upgraded.tasks.indices { upgraded.tasks[i].category = FlowCategories.normalized(upgraded.tasks[i].category) }
        for i in upgraded.history.indices { upgraded.history[i].category = FlowCategories.normalized(upgraded.history[i].category) }
        let buttons = categoryButtons ?? Array(FlowCategories.names(upgraded.tasks.map(\.category) + upgraded.history.map(\.category)).prefix(30))
        upgraded.categoryButtons = try FlowCategories.validatedButtons(buttons)
        return upgraded
    }
}
enum FlowError: LocalizedError {
    case invalidBackup
    var errorDescription: String? { "対応していない、または不正なバックアップです。" }
}
struct FlowClock {
    var calendar: Calendar
    init(timeZone: TimeZone = .current) {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        calendar = c
    }
    func day(_ date: Date) -> Date { calendar.startOfDay(for: date) }
    func today(_ now: Date = Date()) -> Date {
        let start = day(now)
        let cutoff = calendar.date(bySettingHour: 4, minute: 0, second: 0, of: start)!
        return now < cutoff ? calendar.date(byAdding: .day, value: -1, to: start)! : start
    }
    func nextBusinessDay(after date: Date) -> Date {
        var d = day(date)
        repeat { d = calendar.date(byAdding: .day, value: 1, to: d)! }
        while [1, 7].contains(calendar.component(.weekday, from: d))
        return d
    }
    func nextOccurrence(for task: FlowTask, now: Date) -> Date? {
        guard let rule = task.repeatRule else { return nil }
        // Completing early never pulls the next occurrence before its existing due date.
        let base = day(max(task.day, today(now)))
        switch rule {
        case .daily: return calendar.date(byAdding: .day, value: 1, to: base)
        case .weekdays: return nextBusinessDay(after: base)
        case .weekly:
            let weekday = task.repeatAnchorWeekday ?? calendar.component(.weekday, from: task.day)
            let delta = (weekday - calendar.component(.weekday, from: base) + 7) % 7
            return calendar.date(byAdding: .day, value: delta == 0 ? 7 : delta, to: base)
        case .monthly:
            let wanted = task.repeatAnchorDay ?? calendar.component(.day, from: task.day)
            guard let start = calendar.date(from: calendar.dateComponents([.year, .month], from: base)) else { return nil }
            func inMonth(_ month: Date) -> Date? {
                guard let range = calendar.range(of: .day, in: .month, for: month) else { return nil }
                return calendar.date(byAdding: .day, value: min(wanted, range.count) - 1, to: month)
            }
            // If a delayed occurrence was carried into a new month, keep the next anchor in that month.
            if let candidate = inMonth(start), candidate > base { return candidate }
            guard let next = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
            return inMonth(next)
        }
    }
    func label(_ date: Date) -> String {
        let f = DateFormatter(); f.calendar = calendar; f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "ja_JP"); f.dateFormat = "yyyy/MM/dd (E)"
        return f.string(from: date)
    }
    // Explicit dates take precedence; relative dates use the 04:00 business date.
    func recognize(_ text: String, now: Date = Date()) -> Date? {
        let base = today(now)
        let normalized = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text
        let patterns = [#"(?<!\d)(\d{4})[年/-](\d{1,2})[月/-](\d{1,2})日?(?!\d)"#, #"(?<!\d)(\d{1,2})月(\d{1,2})日"#, #"(?<![\d/])(\d{1,2})/(\d{1,2})(?![/\d])"#]
        for (index, pattern) in patterns.enumerated() {
            let regex = try! NSRegularExpression(pattern: pattern)
            guard let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) else { continue }
            let nums = (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: normalized).flatMap { Int(normalized[$0]) } }
            guard nums.count == match.numberOfRanges - 1 else { return nil }
            let year = index == 0 ? nums[0] : calendar.component(.year, from: base)
            let month = index == 0 ? nums[1] : nums[0]
            let date = index == 0 ? nums[2] : nums[1]
            guard let result = calendar.date(from: DateComponents(year: year, month: month, day: date)),
                  calendar.component(.month, from: result) == month, calendar.component(.day, from: result) == date else { return nil }
            if index != 0 && day(result) < base {
                guard let next = calendar.date(from: DateComponents(year: year + 1, month: month, day: date)), calendar.component(.month, from: next) == month, calendar.component(.day, from: next) == date else { return nil }
                return day(next)
            }
            return day(result)
        }
        if normalized.contains("明後日") { return calendar.date(byAdding: .day, value: 2, to: base) }
        if normalized.contains("明日") { return calendar.date(byAdding: .day, value: 1, to: base) }
        if normalized.contains("今日") { return base }
        let weekdays = ["日", "月", "火", "水", "木", "金", "土"]
        for (i, name) in weekdays.enumerated() where normalized.contains(name + "曜") {
            let current = calendar.component(.weekday, from: base)
            var delta = (i + 1 - current + 7) % 7
            if normalized.contains("来週") {
                // Weeks start on Monday, including Sunday -> next Monday.
                let mondayOffset = (current + 5) % 7
                delta = (normalized.contains("再来週") ? 14 : 7) - mondayOffset + (i + 6) % 7
            }
            return calendar.date(byAdding: .day, value: delta, to: base)
        }
        // Period deadlines are calendar dates, including weekends and holidays.
        let year = calendar.component(.year, from: base)
        if ["再来年中", "再来年末"].contains(where: normalized.contains) { return yearEnd(year + 2) }
        if ["来年中", "来年末"].contains(where: normalized.contains) { return yearEnd(year + 1) }
        if ["今年中", "今年末", "今年いっぱい", "年内", "年末"].contains(where: normalized.contains) { return yearEnd(year) }
        if ["再来月中", "再来月末"].contains(where: normalized.contains) { return monthEnd(base, offset: 2) }
        if ["来月中", "来月末"].contains(where: normalized.contains) { return monthEnd(base, offset: 1) }
        if ["今月中", "今月末", "今月いっぱい", "月内", "月末"].contains(where: normalized.contains) { return monthEnd(base, offset: 0) }
        let weekOffset: Int?
        if normalized.contains("再来週中") || normalized.contains("再来週末") { weekOffset = 2 }
        else if normalized.contains("来週中") || normalized.contains("来週末") { weekOffset = 1 }
        else if normalized.contains("今週中") || normalized.contains("今週末") || normalized.contains("週末") { weekOffset = 0 }
        else { weekOffset = nil }
        if let offset = weekOffset {
            let untilSunday = (8 - calendar.component(.weekday, from: base)) % 7
            return calendar.date(byAdding: .day, value: untilSunday + offset * 7, to: base)
        }
        let relative = try! NSRegularExpression(pattern: #"(?<![\d.-])(\d{1,3})(日|週間|か月|ヶ月|カ月|年)後"#)
        if let match = relative.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
           let amountRange = Range(match.range(at: 1), in: normalized),
           let unitRange = Range(match.range(at: 2), in: normalized), let amount = Int(normalized[amountRange]) {
            let unit = String(normalized[unitRange])
            let component: Calendar.Component = unit == "日" || unit == "週間" ? .day : unit == "年" ? .year : .month
            return calendar.date(byAdding: component, value: unit == "週間" ? amount * 7 : amount, to: base)
        }
        let compact = try! NSRegularExpression(pattern: #"(?<![\dA-Za-z/\-])(\d{2})(\d{2})(?![\dA-Za-z年/\-])"#)
        if let match = compact.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
           let m = Range(match.range(at: 1), in: normalized), let d = Range(match.range(at: 2), in: normalized) {
            return recognize("\(normalized[m])/\(normalized[d])", now: now)
        }
        return nil
    }
    private func yearEnd(_ year: Int) -> Date? {
        calendar.date(from: DateComponents(year: year, month: 12, day: 31))
    }
    private func monthEnd(_ base: Date, offset: Int) -> Date? {
        // Anchor on day 1 so January 31 + one month remains February.
        let parts = calendar.dateComponents([.year, .month], from: base)
        guard let start = calendar.date(from: parts),
              let following = calendar.date(byAdding: .month, value: offset + 1, to: start) else { return nil }
        return calendar.date(byAdding: .day, value: -1, to: following)
    }
}
enum FlowSearch {
    static func matches(_ query: String, title: String, note: String = "") -> Bool {
        let terms = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let text = title + "\n" + note
        return terms.allSatisfy { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "ja_JP")) != nil }
    }
}
enum FlowResolutionBlock: Equatable {
    case future, habitRecorded, alreadyCompleted

    var message: String {
        switch self {
        case .future: return "予定日になると達成できます"
        case .habitRecorded: return "今日の習慣は記録済みです"
        case .alreadyCompleted: return "このToDoはすでに達成済みです"
        }
    }
}

enum FlowDisplayedResolution: Equatable {
    case resolved, stale, blocked(FlowResolutionBlock), rolloverLimit
}

extension FlowData {
    mutating func record(_ task: FlowTask, outcome: Outcome, now: Date) {
        history.append(FlowEvent(taskID: task.id, title: task.title, day: task.day, recordedAt: now, outcome: outcome, category: FlowCategories.normalized(task.category), subtasks: task.subtasks, favorite: (outcome == .completed || outcome == .failed) && task.favorite ? true : nil))
    }
    func resolutionBlock(for task: FlowTask, now: Date, clock: FlowClock) -> FlowResolutionBlock? {
        let today = clock.today(now)
        let targetDay = clock.day(task.day)
        guard targetDay <= today else { return .future }
        if task.habitGoal != nil && habitDays.contains(where: { $0.taskID == task.id && $0.day == today }) {
            return .habitRecorded
        }
        // A repeating task keeps its ID when it advances to the next occurrence.
        let alreadyCompleted = history.contains { event in
            event.outcome == .completed && event.taskID == task.id &&
                (clock.day(event.day) == targetDay || clock.today(event.recordedAt) == today)
        }
        return alreadyCompleted ? .alreadyCompleted : nil
    }

    mutating func resolveDisplayedTask(_ displayed: FlowTask, outcome: Outcome, now: Date,
                                       clock: FlowClock, maxCarries: Int) -> FlowDisplayedResolution {
        // Reject a tap from an old occurrence. Edits to its title, star or checklist
        // do not change which occurrence the user tapped.
        guard tasks.contains(where: { $0.id == displayed.id && $0.day == displayed.day }) else { return .stale }
        var updated = self
        guard updated.rollover(now: now, clock: clock, maxCarries: maxCarries) else { return .rolloverLimit }
        guard let current = updated.tasks.first(where: { $0.id == displayed.id }) else { return .stale }
        if outcome == .completed || outcome == .failed,
           let block = updated.resolutionBlock(for: current, now: now, clock: clock) {
            return .blocked(block)
        }
        guard updated.resolve(current.id, outcome: outcome, now: now, clock: clock) else { return .stale }
        self = updated
        return .resolved
    }

    func completedToday(now: Date, clock: FlowClock, category: FlowCategoryFilter = .all,
                        favoritesOnly: Bool = false) -> [FlowEvent] {
        let today = clock.today(now)
        let completed = history.filter { event in
            event.outcome == .completed && clock.today(event.recordedAt) == today
        }.sorted { $0.recordedAt > $1.recordedAt }
        // Keep older duplicate records in history while showing one checked row for the day.
        var shown = Set<UUID>()
        return completed.filter {
            shown.insert($0.taskID).inserted && FlowCategories.matches($0.category, filter: category) &&
                (!favoritesOnly || $0.favorite == true)
        }
    }

    @discardableResult
    mutating func resolve(_ id: UUID, outcome: Outcome, now: Date, clock: FlowClock) -> Bool {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return false }
        let task = tasks[i]
        if outcome == .completed || outcome == .failed {
            guard resolutionBlock(for: task, now: now, clock: clock) == nil else { return false }
        }
        if task.habitGoal != nil {
            if outcome == .completed {
                guard markHabit(id, outcome: .completed, now: now, clock: clock) else { return false }
                saveCompletionUndo(original: task, habitRecord: habitDays.last)
                return true
            }
            if outcome == .failed { return markHabit(id, outcome: .failed, now: now, clock: clock) }
        }
        if task.repeatRule != nil {
            tasks[i].repeatAnchorDay = task.repeatAnchorDay ?? clock.calendar.component(.day, from: task.day)
            tasks[i].repeatAnchorWeekday = task.repeatAnchorWeekday ?? clock.calendar.component(.weekday, from: task.day)
        }
        record(task, outcome: outcome, now: now)
        if outcome == .failed {
            tasks[i].originDay = task.originDay ?? task.day
            tasks[i].day = clock.nextBusinessDay(after: max(task.day, clock.today(now)))
        } else if outcome == .completed, let next = clock.nextOccurrence(for: task, now: now) {
            tasks[i].repeatAnchorDay = task.repeatAnchorDay ?? clock.calendar.component(.day, from: task.day)
            tasks[i].repeatAnchorWeekday = task.repeatAnchorWeekday ?? clock.calendar.component(.weekday, from: task.day)
            tasks[i].day = next
            tasks[i].originDay = nil
            tasks[i].checklist = task.checklist.map { item in var reset = item; reset.isDone = false; return reset }
        } else { tasks.remove(at: i) }
        if outcome == .completed { saveCompletionUndo(original: task) }
        return true
    }
    private mutating func saveCompletionUndo(original: FlowTask, habitRecord: FlowHabitRecord? = nil) {
        let next = tasks.first { $0.id == original.id }
        history[history.count - 1].completionUndo = FlowCompletionUndo(original: original, next: next, habitRecord: habitRecord)
    }

    private func reversibleCompletionIndex(_ eventID: UUID, now: Date, clock: FlowClock) -> Int? {
        guard let index = history.firstIndex(where: { $0.id == eventID }) else { return nil }
        let event = history[index]
        guard event.outcome == .completed, let snapshot = event.completionUndo,
              snapshot.original.id == event.taskID, snapshot.original.day == event.day,
              clock.today(event.recordedAt) == clock.today(now),
              !history[(index + 1)...].contains(where: { $0.taskID == event.taskID }),
              !history[..<index].contains(where: {
                  $0.taskID == event.taskID && $0.outcome == .completed &&
                      (clock.day($0.day) == clock.day(event.day) || clock.today($0.recordedAt) == clock.today(now))
              }),
              tasks.first(where: { $0.id == event.taskID }) == snapshot.next else { return nil }
        if snapshot.original.habitGoal != nil {
            guard let habit = snapshot.habitRecord, habit.taskID == event.taskID,
                  habit.day == clock.today(now), habit.outcome == .completed,
                  habitDays.contains(habit) else { return nil }
        } else if snapshot.habitRecord != nil {
            return nil
        }
        return index
    }

    func canUndoCompletion(_ eventID: UUID, now: Date, clock: FlowClock) -> Bool {
        reversibleCompletionIndex(eventID, now: now, clock: clock) != nil
    }

    @discardableResult
    mutating func undoCompletion(_ eventID: UUID, now: Date, clock: FlowClock) -> Bool {
        guard let index = reversibleCompletionIndex(eventID, now: now, clock: clock),
              let snapshot = history[index].completionUndo else { return false }
        if let taskIndex = tasks.firstIndex(where: { $0.id == snapshot.original.id }) {
            tasks[taskIndex] = snapshot.original
        } else {
            tasks.append(snapshot.original)
        }
        if let habit = snapshot.habitRecord { habitDays.removeAll { $0 == habit } }
        history.remove(at: index)
        return true
    }

    @discardableResult
    mutating func rollover(now: Date, clock: FlowClock, maxCarries: Int = .max) -> Bool {
        let today = clock.today(now)
        var remainingCarries = maxCarries
        let loggedToday = Set(habitDays.filter { $0.day == today }.map(\.taskID))
        for i in tasks.indices {
            if tasks[i].habitGoal != nil {
                if tasks[i].day <= today {
                    if loggedToday.contains(tasks[i].id),
                       let tomorrow = clock.calendar.date(byAdding: .day, value: 1, to: today) {
                        tasks[i].day = tomorrow
                    } else {
                        tasks[i].day = today
                    }
                }
                continue
            }
            while tasks[i].day < today {
                guard remainingCarries > 0 else { return false }
                remainingCarries -= 1
                let previous = tasks[i]
                if previous.repeatRule != nil {
                    tasks[i].repeatAnchorDay = previous.repeatAnchorDay ?? clock.calendar.component(.day, from: previous.day)
                    tasks[i].repeatAnchorWeekday = previous.repeatAnchorWeekday ?? clock.calendar.component(.weekday, from: previous.day)
                }
                record(previous, outcome: .carried, now: now)
                tasks[i].originDay = previous.originDay ?? previous.day
                tasks[i].day = clock.nextBusinessDay(after: previous.day)
            }
        }
        return true
    }
}
