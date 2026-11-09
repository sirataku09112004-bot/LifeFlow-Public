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

