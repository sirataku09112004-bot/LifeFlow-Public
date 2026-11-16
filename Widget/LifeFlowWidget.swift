import SwiftUI
import WidgetKit

private struct TodayEntry: TimelineEntry {
    let date: Date
    let day: FlowWidgetDay?
}

private struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), day: FlowWidgetDay(day: Date(), remaining: 3, percent: 40, titlesVisible: false, tasks: []))
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        let now = Date()
        completion(context.isPreview ? placeholder(in: context) : TodayEntry(date: now, day: read()?.entry(now: now, clock: FlowClock())))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        let clock = FlowClock()
        let snapshot = read()
        let today = clock.today(now)
        var entries = [TodayEntry(date: now, day: snapshot?.entry(now: now, clock: clock))]
        for offset in 1...7 {
            guard let day = clock.calendar.date(byAdding: .day, value: offset, to: today),
                  let boundary = clock.calendar.date(bySettingHour: 4, minute: 0, second: 0, of: day) else { break }
            entries.append(TodayEntry(date: boundary, day: snapshot?.entry(now: boundary, clock: clock)))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func read() -> FlowWidgetSnapshot? {
        guard let file = FlowWidgetContainer.file, let bytes = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(FlowWidgetSnapshot.self, from: bytes)
    }
}

private struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry
    private let accent = Color(red: 0.04, green: 0.37, blue: 0.60)
    private let ink = Color(red: 0.09, green: 0.16, blue: 0.22)
    private let canvas = Color(red: 0.92, green: 0.97, blue: 1.0)

    var body: some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(canvas, for: .widget)
        } else {
            content.padding(12).background(canvas)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 4 : 5) {
            Text("今日のToDo")
                .font(family == .systemSmall ? .subheadline.weight(.bold) : .headline)
                .foregroundStyle(ink)
            if let day = entry.day {
                Text(family == .systemSmall
                     ? "残り \(day.remaining)件 · \(day.percent)%達成"
                     : "残り \(day.remaining)件・達成率 \(day.percent)%")
                    .font(family == .systemSmall ? .caption2 : .subheadline)
                    .foregroundStyle(ink)
                ProgressView(value: Double(day.percent), total: 100)
                    .tint(accent)
                    .accessibilityLabel("今日の達成率 \(day.percent)%")
                if day.titlesVisible {
                    let visibleTasks = Array(day.tasks.prefix(family == .systemSmall ? 2 : 3))
                    if visibleTasks.isEmpty {
                        Text(day.remaining == 0 ? "今日のタスクはありません" : "今日のタスクを読み込み中")
                            .font(.caption2)
                            .foregroundStyle(ink)
                    } else {
                        ForEach(visibleTasks) { task in
                            Link(destination: FlowWidgetRoute.url(for: task.id)) {
                                HStack(alignment: .top, spacing: 5) {
                                    Image(systemName: "circle")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(accent)
                                        .padding(.top, 1)
                                    Text(task.title)
                                        .font(family == .systemSmall ? .caption2.weight(.medium) : .caption.weight(.medium))
                                        .foregroundStyle(ink)
                                        .lineLimit(family == .systemSmall ? 2 : 1)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 7)
                                .padding(.vertical, family == .systemSmall ? 4 : 5)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 7))
                            }
                            .privacySensitive()
                        }
                    }
                } else {
                    Text("ToDo名は非表示")
                        .font(.caption2)
                        .foregroundStyle(ink)
                }
            } else {
                Text("LifeFlowを開いて更新")
                    .font(.caption)
                    .foregroundStyle(ink)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(FlowWidgetRoute.url())
    }
}

@main
struct LifeFlowTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: FlowWidgetContainer.kind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("今日のToDo")
        .description("今日の残り件数、達成率とToDoを表示します。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
