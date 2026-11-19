import AppIntents
import Foundation
import OSLog
import WidgetKit

enum FlowWidgetProbe: String, CaseIterable {
    case standard, widget, app, legacy, foreground, toggle, link

    static let kind = "LifeFlowWidgetProbe"
    static let linkURL = URL(string: "lifeflow://widget-probe")!

    var label: String {
        switch self {
        case .standard: return "A 標準"
        case .widget: return "B 拡張"
        case .app: return "C 本体"
        case .legacy: return "D AltStore方式"
        case .foreground: return "E 起動"
        case .toggle: return "F 切替"
        case .link: return "G URL"
        }
    }
}

struct FlowWidgetProbeReceipt: Codable {
    let date: Date
    let process: String
    let shared: Bool
    let payloadOK: Bool
}

enum FlowWidgetProbeLog {
    private static let logger = Logger(subsystem: "local.private.lifeflow", category: "WidgetProbe")

    private static func resultURL(_ probe: FlowWidgetProbe) -> URL? {
        FlowWidgetContainer.file?.deletingLastPathComponent()
            .appendingPathComponent("widget-probe-\(probe.rawValue).json")
    }

    private static func localKey(_ probe: FlowWidgetProbe) -> String {
        "widget-probe.\(probe.rawValue)"
    }

    static func record(_ probe: FlowWidgetProbe, payloadOK: Bool = true) {
        let isExtension = Bundle.main.bundleURL.pathExtension == "appex"
        let process = isExtension ? "拡張" : "本体"
        let date = Date()
        logger.notice("Probe \(probe.rawValue, privacy: .public) reached \(process, privacy: .public)")
        if let url = resultURL(probe) {
            do {
                let receipt = FlowWidgetProbeReceipt(date: date, process: process, shared: true, payloadOK: payloadOK)
                try FlowWidgetSharedDataFile.writeData(JSONEncoder().encode(receipt), to: url, sharedGroup: true)
                WidgetCenter.shared.reloadTimelines(ofKind: FlowWidgetProbe.kind)
                return
            } catch {
                logger.error("Could not write the shared receipt for \(probe.rawValue, privacy: .public)")
            }
        }
        if !isExtension {
            let receipt = FlowWidgetProbeReceipt(date: date, process: process, shared: false, payloadOK: payloadOK)
            UserDefaults.standard.set(try? JSONEncoder().encode(receipt), forKey: localKey(probe))
        }
    }

    static func sharedReceipt(_ probe: FlowWidgetProbe) -> FlowWidgetProbeReceipt? {
        guard let url = resultURL(probe), let data = try? FlowWidgetSharedDataFile.readData(from: url) else { return nil }
        return try? JSONDecoder().decode(FlowWidgetProbeReceipt.self, from: data)
    }

    static func appReceipt(_ probe: FlowWidgetProbe) -> FlowWidgetProbeReceipt? {
        let shared = sharedReceipt(probe)
        guard let data = UserDefaults.standard.data(forKey: localKey(probe)),
              let local = try? JSONDecoder().decode(FlowWidgetProbeReceipt.self, from: data) else { return shared }
        return shared.map { $0.date > local.date ? $0 : local } ?? local
    }
}

@available(iOS 17.0, *)
struct FlowProbeStandardIntent: AppIntent {
    static let title: LocalizedStringResource = "診断 A 標準"
    static let isDiscoverable = false
    func perform() async throws -> some IntentResult {
        FlowWidgetProbeLog.record(.standard)
        return .result()
    }
}

#if LIFEFLOW_WIDGET_EXTENSION
@available(iOS 17.0, *)
struct FlowProbeWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "診断 B 拡張"
    static let isDiscoverable = false

    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .widgetKitExtension }
    #endif

    func perform() async throws -> some IntentResult {
        FlowWidgetProbeLog.record(.widget)
        return .result()
    }
}
#endif

@available(iOS 17.0, *)
struct FlowProbeAppIntent: AppIntent {
    static let title: LocalizedStringResource = "診断 C 本体"
    static let isDiscoverable = false

    #if compiler(>=6.2)
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .background }
    #endif

    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    func perform() async throws -> some IntentResult {
        FlowWidgetProbeLog.record(.app)
        return .result()
    }
}

@available(iOS 17.0, *)
struct FlowProbeLegacyIntent: AppIntent {
    static let title: LocalizedStringResource = "診断 D AltStore方式"
    static let isDiscoverable = false
    func perform() async throws -> some IntentResult {
        FlowWidgetProbeLog.record(.legacy)
        return .result()
    }
}

@available(iOS, unavailable)
extension FlowProbeLegacyIntent: ForegroundContinuableIntent {}

@available(iOS 17.0, *)
struct FlowProbeForegroundIntent: AppIntent {
    static let title: LocalizedStringResource = "診断 E 起動"
    static let isDiscoverable = false
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        FlowWidgetProbeLog.record(.foreground)
        return .result()
    }
}

@available(iOS 17.0, *)
struct FlowProbeToggleIntent: AppIntent {
    static let title: LocalizedStringResource = "診断 F 切替"
    static let isDiscoverable = false
    static let expected = "lifeflow-probe-v1"

    @Parameter(title: "診断データ") var value: String

    init() {}
    init(value: String) { self.value = value }

    func perform() async throws -> some IntentResult {
        FlowWidgetProbeLog.record(.toggle, payloadOK: value == Self.expected)
        return .result()
    }
}
