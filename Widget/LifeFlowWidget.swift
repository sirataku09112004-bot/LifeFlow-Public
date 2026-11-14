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
    private let accent = Color(red: 0.10, green: 0.45, blue: 0.67)

    var body: some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(Color(red: 0.94, green: 0.98, blue: 1), for: .widget)
        } else {
            content.padding(12).background(Color(red: 0.94, green: 0.98, blue: 1))
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("今日のToDo").font(.headline).foregroundStyle(accent)
            if let day = entry.day {
                Text("残り \(day.remaining)件・達成率 \(day.percent)%")
                    .font(family == .systemSmall ? .footnote : .subheadline)
                    .foregroundStyle(Color(red: 0.14, green: 0.29, blue: 0.39))
                if family == .systemMedium {
                    if day.titlesVisible {
                        ForEach(day.tasks) { task in
                            Link(destination: FlowWidgetRoute.url(for: task.id)) {
                                Label(task.title, systemImage: "square").font(.caption).lineLimit(1)
                                    .privacySensitive()
                            }
                        }
                    } else {
                        Text("ToDo名は非表示").font(.caption).foregroundStyle(accent)
                    }
                }
            } else {
                Text("LifeFlowを開いて更新").font(.caption).foregroundStyle(accent)
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
        .description("今日の残り件数と達成率を表示します。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
