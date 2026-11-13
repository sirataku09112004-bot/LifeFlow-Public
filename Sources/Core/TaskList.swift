import Foundation

enum FlowPriority: String, Codable, CaseIterable, Identifiable {
    case high, normal, low
    var id: String { rawValue }
    var label: String { switch self { case .high: return "高い"; case .normal: return "通常"; case .low: return "低い" } }
    var rank: Int { switch self { case .high: return 0; case .normal: return 1; case .low: return 2 } }
}
struct FlowTaskList {
    let all: [FlowTask]
    let today: [FlowTask]
    let favorites: [FlowTask]
    init(tasks: [FlowTask], query: String, category: FlowCategoryFilter = .all, now: Date, clock: FlowClock) {
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
        today = matched.filter { $0.day <= clock.today(now) }
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
