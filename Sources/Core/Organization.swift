import Foundation

struct FlowSubtask: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var isDone = false
}
enum FlowCategoryFilter: Hashable {
    case all, uncategorized, named(String)
}
enum FlowCategories {
    static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
    static func names(_ values: [String?]) -> [String] { Array(Set(values.compactMap(normalized))).sorted() }
    static func validatedButtons(_ values: [String]) throws -> [String] {
        let names = values.compactMap { normalized($0) }
        guard values.count <= 30, names.count == values.count,
              Set(names).count == names.count, names.allSatisfy({ $0.count <= 40 }) else { throw FlowError.invalidBackup }
        return names
    }
    static func matches(_ value: String?, filter: FlowCategoryFilter) -> Bool {
        switch filter {
        case .all: return true
        case .uncategorized: return normalized(value) == nil
        case .named(let name): return normalized(value) == normalized(name)
        }
    }
}
extension FlowTask {
    var checklist: [FlowSubtask] {
        get { subtasks ?? [] }
        set { subtasks = newValue.isEmpty ? nil : newValue }
    }
    var completedSubtasks: Int { checklist.filter(\.isDone).count }
}
extension FlowData {
    var registeredCategories: [String] {
        categoryButtons ?? Array(FlowCategories.names(tasks.map(\.category) + history.map(\.category)).prefix(30))
    }
    @discardableResult mutating func toggleSubtask(taskID: UUID, subtaskID: UUID) -> Bool {
        guard let i = tasks.firstIndex(where: { $0.id == taskID }),
              let j = tasks[i].checklist.firstIndex(where: { $0.id == subtaskID }) else { return false }
        var items = tasks[i].checklist
        items[j].isDone.toggle()
        tasks[i].checklist = items
        return true
    }
}
