import Foundation

struct FlowCalendarMonth {
    struct Item: Identifiable {
        let task: FlowTask
        let isDeadline: Bool
        let isPlanned: Bool

        var id: UUID { task.id }
    }

    let start: Date
    let leadingDays: Int
    let days: [Date]
    let itemsByDay: [Date: [Item]]

    init(containing date: Date, tasks: [FlowTask], clock: FlowClock) {
        let calendar = clock.calendar
        let month = calendar.dateInterval(of: .month, for: date)!
        let dayCount = calendar.range(of: .day, in: .month, for: month.start)!.count
        start = month.start
        leadingDays = calendar.component(.weekday, from: month.start) - 1
        days = (0..<dayCount).compactMap { calendar.date(byAdding: .day, value: $0, to: month.start) }

        var byDay: [Date: [Item]] = [:]
        for task in tasks {
            let deadline = clock.day(task.deadline)
            let planned = task.plannedDay.map(clock.day)
            if month.contains(deadline), deadline < month.end {
                byDay[deadline, default: []].append(Item(task: task, isDeadline: true, isPlanned: planned == deadline))
            }
            if let planned, planned != deadline, month.contains(planned), planned < month.end {
                byDay[planned, default: []].append(Item(task: task, isDeadline: false, isPlanned: true))
            }
        }
        itemsByDay = byDay.mapValues { items in
            items.sorted {
                if $0.isDeadline != $1.isDeadline { return $0.isDeadline }
                if $0.task.title != $1.task.title { return $0.task.title < $1.task.title }
                return $0.id.uuidString < $1.id.uuidString
            }
        }
    }
}
