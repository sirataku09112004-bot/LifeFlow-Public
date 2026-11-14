import Foundation

struct FlowWidgetDay: Codable, Equatable {
    struct Task: Codable, Equatable, Identifiable {
        let id: UUID
        let title: String
    }

    let day: Date
    let remaining: Int
    let percent: Int
    let titlesVisible: Bool
    let tasks: [Task]
}

struct FlowWidgetSnapshot: Codable, Equatable {
    let timeZone: String
    let days: [FlowWidgetDay]

    init(data: FlowData, now: Date, clock: FlowClock, showTitles: Bool) {
        timeZone = clock.calendar.timeZone.identifier
        let today = clock.today(now)
        var entries: [FlowWidgetDay] = []
        for offset in 0..<7 {
            guard let day = clock.calendar.date(byAdding: .day, value: offset, to: today),
                  let boundary = clock.calendar.date(bySettingHour: 4, minute: 0, second: 0, of: day) else { break }
            let date = offset == 0 ? now : boundary
            var projected = data
            guard projected.rollover(now: date, clock: clock, maxCarries: 10_000) else { break }
            let done = projected.completedToday(now: date, clock: clock)
            let doneIDs = Set(done.map(\.taskID))
            let list = FlowTaskList(tasks: projected.tasks, query: "", now: date, clock: clock,
                                    todayOrder: projected.todayOrder ?? [])
            let pending = list.today.filter { !doneIDs.contains($0.id) }
            let progress = FlowTodayProgress(data: projected, pending: pending, completed: done,
                                             now: date, clock: clock, category: .all, favoritesOnly: false)
            entries.append(FlowWidgetDay(day: day, remaining: pending.count, percent: progress.percent,
                                         titlesVisible: showTitles,
                                         tasks: showTitles ? pending.prefix(3).map {
                                             FlowWidgetDay.Task(id: $0.id, title: $0.title)
                                         } : []))
        }
        days = entries
    }

    func entry(now: Date, clock: FlowClock) -> FlowWidgetDay? {
        guard timeZone == clock.calendar.timeZone.identifier else { return nil }
        return days.first { $0.day == clock.today(now) }
    }
}
