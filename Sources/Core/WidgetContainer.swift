import Foundation

enum FlowWidgetContainer {
    static let identifier = "group.local.private.lifeflow.widget"
    static let kind = "LifeFlowToday"
    static let undatedKind = "LifeFlowUndated"
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
    let displayedDay: Date?

    init?(_ url: URL) {
        guard url.scheme == "lifeflow", url.host == "todo" else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func date(_ name: String) -> Date? {
            guard let value = query.first(where: { $0.name == name })?.value,
                  let seconds = Double(value), seconds.isFinite else { return nil }
            let result = Date(timeIntervalSince1970: seconds)
            return (Date.distantPast...Date.distantFuture).contains(result) ? result : nil
        }
        if path.isEmpty {
            taskID = nil
            occurrenceDay = nil
            displayedDay = nil
        } else if path.count == 1, let id = UUID(uuidString: path[0]) {
            taskID = id
            occurrenceDay = nil
            displayedDay = nil
        } else if path.count == 2, path[0] == "complete", let id = UUID(uuidString: path[1]),
                  let occurrence = date("day") {
            let displayed = date("shown")
            guard displayed != nil || !query.contains(where: { $0.name == "shown" }) else { return nil }
            taskID = id
            occurrenceDay = occurrence
            displayedDay = displayed
        } else {
            return nil
        }
    }

    static func url(for taskID: UUID? = nil) -> URL {
        if let taskID { return URL(string: "lifeflow://todo/\(taskID.uuidString)")! }
        return URL(string: "lifeflow://todo")!
    }

    static func completionURL(for taskID: UUID, occurrenceDay: Date, displayedDay: Date) -> URL {
        var components = URLComponents()
        components.scheme = "lifeflow"
        components.host = "todo"
        components.path = "/complete/\(taskID.uuidString)"
        components.queryItems = [
            URLQueryItem(name: "day", value: String(occurrenceDay.timeIntervalSince1970)),
            URLQueryItem(name: "shown", value: String(displayedDay.timeIntervalSince1970))
        ]
        return components.url!
    }
}
