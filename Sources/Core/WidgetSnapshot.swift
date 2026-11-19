import Foundation

struct FlowWidgetDay: Codable, Equatable {
    struct Task: Codable, Equatable, Identifiable {
        let id: UUID
        let title: String
        let occurrenceDay: Date?

        init(id: UUID, title: String, occurrenceDay: Date? = nil) {
            self.id = id
            self.title = title
            self.occurrenceDay = occurrenceDay
        }
    }

    let day: Date
    let remaining: Int
    let percent: Int
    let titlesVisible: Bool
    let tasks: [Task]
    let upcomingTasks: [Task]?

    init(day: Date, remaining: Int, percent: Int, titlesVisible: Bool, tasks: [Task],
         upcomingTasks: [Task]? = nil) {
        self.day = day
        self.remaining = remaining
        self.percent = percent
        self.titlesVisible = titlesVisible
        self.tasks = tasks
        self.upcomingTasks = upcomingTasks
    }
}

struct FlowWidgetSnapshot: Codable, Equatable {
    let timeZone: String
    let days: [FlowWidgetDay]
    let opensForCompletion: Bool?

    init(data: FlowData, now: Date, clock: FlowClock, showTitles: Bool, opensForCompletion: Bool = false) {
        timeZone = clock.calendar.timeZone.identifier
        self.opensForCompletion = opensForCompletion
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
            let upcoming = showTitles ? Array(list.all.lazy
                .filter { !$0.belongsToToday(day, clock: clock) }
                .prefix(4)
                .map { FlowWidgetDay.Task(id: $0.id, title: $0.title, occurrenceDay: $0.day) }) : []
            let progress = FlowTodayProgress(data: projected, pending: pending, completed: done,
                                             now: date, clock: clock, category: .all, favoritesOnly: false)
            entries.append(FlowWidgetDay(day: day, remaining: pending.count, percent: progress.percent,
                                         titlesVisible: showTitles,
                                         tasks: showTitles ? pending.prefix(4).map {
                                             FlowWidgetDay.Task(id: $0.id, title: $0.title, occurrenceDay: $0.day)
                                         } : [],
                                         upcomingTasks: upcoming))
        }
        days = entries
    }

    func entry(now: Date, clock: FlowClock) -> FlowWidgetDay? {
        guard timeZone == clock.calendar.timeZone.identifier else { return nil }
        return days.first { $0.day == clock.today(now) }
    }
}
