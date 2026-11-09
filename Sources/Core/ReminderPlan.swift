import Foundation

struct FlowReminderSettings: Codable, Equatable {
    var hour = 9
    var minute = 0
    var onDueDay = true
    var onPreviousDay = false
    var previousHour = 18
    var previousMinute = 0
    var weekdays = Array(1...7) // Calendar weekday: Sunday = 1.
    var favoritesOnly = false
    var sound = true
    var showTitle = true

    func normalized() -> Self {
        var copy = self
        copy.hour = (0...23).contains(hour) ? hour : 9
        copy.minute = (0...59).contains(minute) ? minute : 0
        copy.previousHour = (0...23).contains(previousHour) ? previousHour : 18
        copy.previousMinute = (0...59).contains(previousMinute) ? previousMinute : 0
        copy.weekdays = Array(Set(weekdays.filter { (1...7).contains($0) })).sorted()
        return copy
    }
    static func load(_ bytes: Data?, legacyHour: Int?) -> Self {
        if let bytes, let stored = try? JSONDecoder().decode(Self.self, from: bytes) { return stored.normalized() }
        var settings = Self()
        if let legacyHour, (4...23).contains(legacyHour) { settings.hour = legacyHour }
        return settings
    }
}

struct FlowReminder: Identifiable {
    let id: UUID // Task ID, kept for compatibility with the original planner.
    let title: String
    let fireDate: Date
    var previousDay = false
    var requestID: String { "lifeflow.task.\(id.uuidString).\(previousDay ? "previous" : "due")" }
    var heading: String { previousDay ? "LifeFlow・明日のToDo" : "LifeFlow・今日のToDo" }
}

enum FlowReminderPlan {
    static func make(tasks: [FlowTask], hour: Int, now: Date, clock: FlowClock, limit: Int = 60) -> [FlowReminder] {
        guard (4...23).contains(hour) else { return [] }
        var settings = FlowReminderSettings(); settings.hour = hour
        return make(tasks: tasks, settings: settings, now: now, clock: clock, limit: limit)
    }
    static func make(tasks: [FlowTask], settings: FlowReminderSettings, now: Date, clock: FlowClock, limit: Int = 60) -> [FlowReminder] {
        guard limit > 0 else { return [] }
        let settings = settings.normalized()
        var plan: [FlowReminder] = []
        for task in tasks where task.muteReminder != true && (!settings.favoritesOnly || task.favorite) {
            for previous in [false, true] {
                guard previous ? settings.onPreviousDay : settings.onDueDay,
                      let day = clock.calendar.date(byAdding: .day, value: previous ? -1 : 0, to: clock.day(task.day)),
                      let date = clock.calendar.date(bySettingHour: previous ? settings.previousHour : settings.hour,
                                                     minute: previous ? settings.previousMinute : settings.minute,
                                                     second: 0, of: day),
                      date > now, settings.weekdays.contains(clock.calendar.component(.weekday, from: date)) else { continue }
                plan.append(FlowReminder(id: task.id, title: task.title, fireDate: date, previousDay: previous))
            }
        }
        return Array(plan.sorted { a, b in
            a.fireDate == b.fireDate ? a.requestID < b.requestID : a.fireDate < b.fireDate
        }.prefix(min(limit, 60)))
    }
}
