import Foundation

enum FlowWidgetContainer {
    static let identifier = "group.local.private.lifeflow.widget"
    static let kind = "LifeFlowToday"
    static let fileName = "today-widget.json"

    static func groupIDs(_ signed: [String]) -> [String] {
        signed.filter { $0 == identifier || $0.hasPrefix(identifier + ".") } + [identifier]
    }

    #if os(iOS)
    static var file: URL? {
        let groups = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? []
        return groupIDs(groups).lazy.compactMap {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0)
        }.first?.appendingPathComponent(fileName)
    }
    #endif
}

struct FlowWidgetRoute {
    let taskID: UUID?

    init?(_ url: URL) {
        guard url.scheme == "lifeflow", url.host == "todo" else { return nil }
        if url.path.isEmpty || url.path == "/" {
            taskID = nil
        } else {
            guard url.pathComponents.count == 2, let id = UUID(uuidString: url.lastPathComponent) else { return nil }
            taskID = id
        }
    }

    static func url(for taskID: UUID? = nil) -> URL {
        if let taskID { return URL(string: "lifeflow://todo/\(taskID.uuidString)")! }
        return URL(string: "lifeflow://todo")!
    }
}
