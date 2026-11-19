import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct LifeFlowProbeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "LifeFlowProbeControl") {
            ControlWidgetButton(action: FlowProbeStandardIntent()) {
                Label("LifeFlow 診断A", systemImage: "checkmark.circle")
            }
        }
        .displayName("LifeFlow 診断A")
        .description("ホーム画面と同じAを呼び出します。")
    }
}

@available(iOS 17.0, *)
struct LifeFlowProbeConfigurationWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "LifeFlowWidgetConfigurationProbe",
                               intent: FlowProbeConfigurationIntent.self,
                               provider: Provider()) { entry in
            VStack(alignment: .leading, spacing: 5) {
                Text("設定読み込み診断")
                    .font(.caption.weight(.bold))
                Text(entry.choice ?? "編集で選択")
                    .font(.caption2)
                    .lineLimit(1)
                Button(intent: FlowProbeStandardIntent()) {
                    Label("A 標準", systemImage: "circle")
                        .font(.caption2.weight(.semibold))
                        .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("probe-configured-standard")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(for: .widget) { Color(.systemGroupedBackground) }
        }
        .configurationDisplayName("設定読み込み診断")
        .description("編集画面で診断用の選択肢を読み込みます。")
        .supportedFamilies([.systemSmall])
    }

    struct Entry: TimelineEntry {
        let date = Date()
        let choice: String?
    }

    struct Provider: AppIntentTimelineProvider {
        func placeholder(in context: Context) -> Entry { Entry(choice: nil) }

        func snapshot(for configuration: FlowProbeConfigurationIntent, in context: Context) async -> Entry {
            Entry(choice: configuration.choice)
        }

        func timeline(for configuration: FlowProbeConfigurationIntent, in context: Context) async -> Timeline<Entry> {
            Timeline(entries: [Entry(choice: configuration.choice)], policy: .never)
        }
    }
}

@available(iOS 17.0, *)
struct FlowProbeConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "設定読み込み診断"

    @Parameter(title: "診断用の選択肢", optionsProvider: FlowProbeConfigurationOptions())
    var choice: String?
}

@available(iOS 17.0, *)
struct FlowProbeConfigurationOptions: DynamicOptionsProvider {
    func results() async throws -> [String] {
        FlowWidgetProbeLog.record(.configuration)
        return ["診断OK 1", "診断OK 2"]
    }
}
