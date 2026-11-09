import Foundation

enum FlowHabitOutcome: String, Codable {
    case completed, failed, rest

    var label: String {
        switch self {
        case .completed: return "達成"
        case .failed: return "失敗"
        case .rest: return "休養"
        }
    }
}

struct FlowHabitRecord: Codable, Equatable {
    let taskID: UUID
    let day: Date
    let outcome: FlowHabitOutcome

    struct Key: Hashable {
        let taskID: UUID
        let day: Date
    }

    var key: Key { Key(taskID: taskID, day: day) }
}

extension FlowData {
    var habitDays: [FlowHabitRecord] {
        get { habitRecords ?? [] }
        set { habitRecords = newValue }
    }

    @discardableResult
    mutating func markHabit(_ id: UUID, outcome: FlowHabitOutcome, now: Date, clock: FlowClock) -> Bool {
        let today = clock.today(now)
        let key = FlowHabitRecord.Key(taskID: id, day: today)
        guard let index = tasks.firstIndex(where: { $0.id == id && $0.habitGoal != nil && $0.day <= today }),
              !habitDays.contains(where: { $0.key == key }),
              let next = clock.calendar.date(byAdding: .day, value: 1, to: today) else { return false }
        let task = tasks[index]
        habitDays.append(FlowHabitRecord(taskID: id, day: today, outcome: outcome))
        switch outcome {
        case .completed: record(task, outcome: .completed, now: now)
        case .failed: record(task, outcome: .failed, now: now)
        case .rest: break
        }
        tasks[index].day = next
        tasks[index].originDay = nil
        tasks[index].checklist = task.checklist.map {
            var item = $0
            item.isDone = false
            return item
        }
        return true
    }
}

struct FlowHabitCalendar {
    var clock: FlowClock
    let today: Date
    let records: [Date: FlowHabitOutcome]

    init(taskID: UUID, days: [FlowHabitRecord], now: Date, clock: FlowClock) {
        self.clock = clock
        today = clock.today(now)
        records = days.reduce(into: [:]) { byDay, record in
            if record.taskID == taskID { byDay[record.day] = record.outcome }
        }
    }

    func interval(month: Bool, offset: Int) -> DateInterval? {
        var calendar = clock.calendar
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        let component: Calendar.Component = month ? .month : .weekOfYear
        guard let base = calendar.dateInterval(of: component, for: today),
              let shifted = calendar.date(byAdding: component, value: offset, to: base.start) else { return nil }
        return calendar.dateInterval(of: component, for: shifted)
    }

    func days(in interval: DateInterval) -> [Date] {
        var days: [Date] = []
        var day = interval.start
        while day < interval.end {
            days.append(day)
            guard let next = clock.calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    func counts(in interval: DateInterval) -> (completed: Int, failed: Int) {
        let outcomes = days(in: interval).compactMap { records[$0] }
        return (outcomes.filter { $0 == .completed }.count, outcomes.filter { $0 == .failed }.count)
    }

    var streak: Int {
        var day = today
        if records[day] == nil {
            guard let yesterday = clock.calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while let outcome = records[day], outcome != .failed {
            if outcome == .completed { count += 1 }
            guard let previous = clock.calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
}
