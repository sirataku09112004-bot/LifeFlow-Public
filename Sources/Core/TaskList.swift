import Foundation

enum FlowPriority: String, Codable, CaseIterable, Identifiable {
    case high, normal, low
    var id: String { rawValue }
    var label: String { switch self { case .high: return "高い"; case .normal: return "通常"; case .low: return "低い" } }
    var rank: Int { switch self { case .high: return 0; case .normal: return 1; case .low: return 2 } }
}
extension FlowTask {
    func isPlannedToday(_ today: Date, clock: FlowClock) -> Bool {
        plannedDay.map(clock.day) == today
    }

    func belongsToToday(_ today: Date, clock: FlowClock) -> Bool {
        clock.day(day) <= today || isPlannedToday(today, clock: clock)
    }
}

extension FlowData {
    mutating func setPlannedToday(_ id: UUID, enabled: Bool, now: Date, clock: FlowClock) -> Bool {
        guard let index = tasks.firstIndex(where: { $0.id == id && $0.habitGoal == nil }) else { return false }
        tasks[index].plannedDay = enabled ? clock.today(now) : nil
        return true
    }

    mutating func changeDeadline(_ id: UUID, to date: Date, clock: FlowClock) -> Bool {
        guard let index = tasks.firstIndex(where: { $0.id == id && $0.habitGoal == nil }) else { return false }
        tasks[index].day = clock.day(date)
        tasks[index].originDay = nil
        tasks[index].repeatAnchorDay = tasks[index].repeatRule.map { _ in clock.calendar.component(.day, from: date) }
        tasks[index].repeatAnchorWeekday = tasks[index].repeatRule.map { _ in clock.calendar.component(.weekday, from: date) }
        return true
    }

    mutating func reorderToday(_ visible: [UUID], to reordered: [UUID], now: Date, clock: FlowClock) -> Bool {
        let pending = FlowTaskList(tasks: tasks, query: "", now: now, clock: clock, todayOrder: todayOrder ?? []).today
        let completed = Set(completedToday(now: now, clock: clock).map(\.taskID))
        let available = pending.map(\.id).filter { !completed.contains($0) }
        let changed = Set(visible)
        guard changed.count == visible.count, reordered.count == visible.count,
              Set(reordered) == changed, changed.isSubset(of: Set(available)) else { return false }

        // Replace the visible slots and keep the relative positions of tasks hidden by a filter.
        var order = todayOrder ?? []
        var known = Set(order)
        order.append(contentsOf: available.filter { known.insert($0).inserted })
        var replacement = reordered.makeIterator()
        todayOrder = order.map { changed.contains($0) ? replacement.next()! : $0 }
        return true
    }
}

struct FlowTaskList {
    let all: [FlowTask]
    let today: [FlowTask]
    let favorites: [FlowTask]
    init(tasks: [FlowTask], query: String, category: FlowCategoryFilter = .all, now: Date, clock: FlowClock, todayOrder: [UUID] = []) {
        let matched = tasks.filter {
            FlowCategories.matches($0.category, filter: category) && FlowSearch.matches(query, title: $0.title, note: $0.note + "\n" + $0.checklist.map(\.title).joined(separator: "\n"))
        }.sorted { a, b in
            if a.day != b.day { return a.day < b.day }
            let aRank = (a.priority ?? .normal).rank
            let bRank = (b.priority ?? .normal).rank
            if aRank != bRank { return aRank < bRank }
            if a.favorite != b.favorite { return a.favorite }
            if a.title != b.title { return a.title < b.title }
            return a.id.uuidString < b.id.uuidString
        }
        all = matched
        let date = clock.today(now)
        var ranks: [UUID: Int] = [:]
        for (index, id) in todayOrder.enumerated() where ranks[id] == nil { ranks[id] = index }
        let pending = matched.filter { $0.belongsToToday(date, clock: clock) }
        today = pending.enumerated().sorted {
            let left = ranks[$0.element.id] ?? Int.max
            let right = ranks[$1.element.id] ?? Int.max
            return left == right ? $0.offset < $1.offset : left < right
        }.map(\.element)
        favorites = matched.filter(\.favorite)
    }
}


struct FlowTodayProgress {
    let completed: Int
    let total: Int
    var fraction: Double { total == 0 ? 0 : Double(completed) / Double(total) }
    var percent: Int { total == 0 ? 0 : (100 * completed) / total }

    init(data: FlowData, pending: [FlowTask], completed: [FlowEvent],
         now: Date, clock: FlowClock, category: FlowCategoryFilter, favoritesOnly: Bool) {
        let today = clock.today(now)
        let doneIDs = Set(completed.map(\.taskID))
        var eligible = Set(pending.map(\.id))
        // Failed items remain part of today's workload after they are moved to a future date.
        // A later deletion removes the failed item from today's workload.
        var lastFailureOrDeletion: [UUID: FlowEvent] = [:]
        for event in data.history where clock.today(event.recordedAt) == today {
            if event.outcome == .failed || event.outcome == .deleted {
                lastFailureOrDeletion[event.taskID] = event
            }
        }
        for event in lastFailureOrDeletion.values where event.outcome == .failed {
            if FlowCategories.matches(event.category, filter: category) && (!favoritesOnly || event.favorite == true) {
                eligible.insert(event.taskID)
            }
        }
        self.completed = doneIDs.count
        total = eligible.union(doneIDs).count
    }
}
