import Foundation

struct FlowWidgetDay: Codable, Equatable {
    static let smallTaskLimit = 5
    static let mediumTaskLimit = 6
    static let undatedTaskLimit = 7

    struct Task: Codable, Equatable, Identifiable {
        let id: UUID
        let title: String
        let occurrenceDay: Date?
        let completionBlocked: Bool?

        init(id: UUID, title: String, occurrenceDay: Date? = nil, completionBlocked: Bool? = nil) {
            self.id = id
            self.title = title
            self.occurrenceDay = occurrenceDay
            self.completionBlocked = completionBlocked
        }
    }

    struct Undated: Codable, Equatable {
        let remaining: Int
        let tasks: [Task]
    }

    let day: Date
    let remaining: Int
    let percent: Int
    let titlesVisible: Bool
    let tasks: [Task]
    let upcomingTasks: [Task]?
    let undated: Undated?

    init(day: Date, remaining: Int, percent: Int, titlesVisible: Bool, tasks: [Task],
         upcomingTasks: [Task]? = nil, undated: Undated? = nil) {
        self.day = day
        self.remaining = remaining
        self.percent = percent
        self.titlesVisible = titlesVisible
        self.tasks = tasks
        self.upcomingTasks = upcomingTasks
        self.undated = undated
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
            let undatedTasks = list.all.filter { !$0.hasDeadline }
            let undated = FlowWidgetDay.Undated(
                remaining: undatedTasks.count,
                tasks: showTitles ? undatedTasks.prefix(FlowWidgetDay.undatedTaskLimit).map {
                    FlowWidgetDay.Task(id: $0.id, title: $0.title, occurrenceDay: $0.day)
                } : [])
            let upcoming = showTitles ? Array(list.all.lazy
                .filter { $0.hasDeadline && !$0.belongsToToday(day, clock: clock) }
                .prefix(FlowWidgetDay.mediumTaskLimit)
                .map {
                    FlowWidgetDay.Task(id: $0.id, title: $0.title, occurrenceDay: $0.day,
                                       completionBlocked: projected.resolutionBlock(for: $0, now: date, clock: clock) != nil)
                }) : []
            let progress = FlowTodayProgress(data: projected, pending: pending, completed: done,
                                             now: date, clock: clock, category: .all, favoritesOnly: false)
            entries.append(FlowWidgetDay(day: day, remaining: pending.count, percent: progress.percent,
                                         titlesVisible: showTitles,
                                         tasks: showTitles ? pending.prefix(FlowWidgetDay.mediumTaskLimit).map {
                                             FlowWidgetDay.Task(id: $0.id, title: $0.title, occurrenceDay: $0.day)
                                         } : [],
                                         upcomingTasks: upcoming, undated: undated))
        }
        days = entries
    }

    func entry(now: Date, clock: FlowClock) -> FlowWidgetDay? {
        guard timeZone == clock.calendar.timeZone.identifier else { return nil }
        return days.first { $0.day == clock.today(now) }
    }
}
