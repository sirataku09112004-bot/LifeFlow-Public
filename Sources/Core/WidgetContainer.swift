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

    static var dataFile: URL? {
        file?.deletingLastPathComponent().appendingPathComponent("lifeflow.shared.json")
    }
    #endif
}

struct FlowWidgetRoute {
    let taskID: UUID?
    let occurrenceDay: Date?

    init?(_ url: URL) {
        guard url.scheme == "lifeflow", url.host == "todo" else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }
        if path.isEmpty {
            taskID = nil
            occurrenceDay = nil
        } else if path.count == 1, let id = UUID(uuidString: path[0]) {
            taskID = id
            occurrenceDay = nil
        } else if path.count == 2, path[0] == "complete", let id = UUID(uuidString: path[1]),
                  let seconds = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                    .first(where: { $0.name == "day" })?.value.flatMap({ Double($0) }) {
            taskID = id
            occurrenceDay = Date(timeIntervalSince1970: seconds)
        } else {
            return nil
        }
    }

    static func url(for taskID: UUID? = nil) -> URL {
        if let taskID { return URL(string: "lifeflow://todo/\(taskID.uuidString)")! }
        return URL(string: "lifeflow://todo")!
    }

    static func completionURL(for taskID: UUID, occurrenceDay: Date) -> URL {
        var components = URLComponents()
        components.scheme = "lifeflow"
        components.host = "todo"
        components.path = "/complete/\(taskID.uuidString)"
        components.queryItems = [URLQueryItem(name: "day", value: String(occurrenceDay.timeIntervalSince1970))]
        return components.url!
    }
}
