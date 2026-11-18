import SwiftUI
import WidgetKit

private struct TodayEntry: TimelineEntry {
    let date: Date
    let day: FlowWidgetDay?
    var sharedStorageAvailable = true
    var opensForCompletion = false
}

private struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), day: FlowWidgetDay(day: Date(), remaining: 3, percent: 40, titlesVisible: false, tasks: []))
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        let now = Date()
        let file = FlowWidgetContainer.file
        let snapshot = read(file, now: now, clock: FlowClock())
        completion(context.isPreview ? placeholder(in: context) :
            TodayEntry(date: now, day: snapshot?.entry(now: now, clock: FlowClock()),
                       sharedStorageAvailable: file != nil, opensForCompletion: snapshot?.opensForCompletion ?? false))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        let clock = FlowClock()
        let file = FlowWidgetContainer.file
        let snapshot = read(file, now: now, clock: clock)
        let opensForCompletion = snapshot?.opensForCompletion ?? false
        let today = clock.today(now)
        let current = TodayEntry(date: now, day: snapshot?.entry(now: now, clock: clock),
                                 sharedStorageAvailable: file != nil, opensForCompletion: opensForCompletion)
        var entries = [current]
        guard current.day != nil else {
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
            return
        }
        for offset in 1..<7 {
            guard let day = clock.calendar.date(byAdding: .day, value: offset, to: today),
                  let boundary = clock.calendar.date(bySettingHour: 4, minute: 0, second: 0, of: day),
                  let next = snapshot?.entry(now: boundary, clock: clock) else { break }
            entries.append(TodayEntry(date: boundary, day: next, opensForCompletion: opensForCompletion))
        }
        let finalDay = entries.last?.day?.day ?? today
        let nextDay = clock.calendar.date(byAdding: .day, value: 1, to: finalDay) ?? finalDay
        let boundary = clock.calendar.date(bySettingHour: 4, minute: 0, second: 0, of: nextDay) ?? now
        entries.append(TodayEntry(date: boundary, day: nil))
        completion(Timeline(entries: entries, policy: .after(boundary)))
    }

    private func read(_ file: URL?, now: Date, clock: FlowClock) -> FlowWidgetSnapshot? {
        guard let file, let bytes = try? FlowWidgetSharedDataFile.readData(from: file),
              let snapshot = try? JSONDecoder().decode(FlowWidgetSnapshot.self, from: bytes) else { return nil }
        guard let dataFile = FlowWidgetContainer.dataFile,
              let sharedBytes = try? FlowWidgetSharedDataFile.readData(from: dataFile),
              let data = try? FlowWidgetSharedDataFile.decode(sharedBytes) else { return snapshot }
        // Keep the display preference in the snapshot; get task state from the shared save.
        return FlowWidgetSnapshot(data: data, now: now, clock: clock,
                                  showTitles: snapshot.days.first?.titlesVisible ?? false,
                                  opensForCompletion: snapshot.opensForCompletion ?? false)
    }
}

private struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: TodayEntry
    private let accent = Color(red: 0.04, green: 0.37, blue: 0.60)
    private var ink: Color { renderingMode == .fullColor ? Color(red: 0.09, green: 0.16, blue: 0.22) : .primary }
    private let canvas = Color(red: 0.92, green: 0.97, blue: 1.0)

    var body: some View {
        if #available(iOS 17.0, *) {
            content.padding(8).containerBackground(canvas, for: .widget)
        } else {
            content.padding(8).background(canvas)
        }
    }

    private var content: some View {
        GeometryReader { geometry in
            layout(rowHeight: min(26, max(14, floor((geometry.size.height - 38) / 4))))
        }
        .widgetURL(FlowWidgetRoute.url())
    }

    private func layout(rowHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("今日のToDo")
                .font(.caption.weight(.bold))
                .foregroundStyle(ink)
            if let day = entry.day {
                Text("残り \(day.remaining)件 · \(day.percent)%達成")
                    .font(.system(size: 9))
                    .foregroundStyle(ink)
                if family != .systemSmall {
                    ProgressView(value: Double(day.percent), total: 100)
                        .tint(accent)
                        .accessibilityLabel("今日の達成率 \(day.percent)%")
                }
                if day.titlesVisible {
                    let visibleTasks = Array(day.tasks.prefix(4))
                    if visibleTasks.isEmpty {
                        Text(day.remaining == 0 ? "今日のタスクはありません" : "今日のタスクを読み込み中")
                            .font(.caption2)
                            .foregroundStyle(ink)
                    } else {
                        ForEach(visibleTasks) { task in
                            taskRow(task, displayedDay: day.day, height: rowHeight)
                        }
                    }
                } else {
                    Text("LifeFlowの設定でToDo名を表示できます")
                        .font(.caption2)
                        .foregroundStyle(ink)
                }
            } else {
                Text(entry.sharedStorageAvailable ? "LifeFlowを開いて更新" : "LifeFlowとデータを共有できません")
                    .font(.caption)
                    .foregroundStyle(ink)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func taskRow(_ task: FlowWidgetDay.Task, displayedDay: Date, height: CGFloat) -> some View {
        HStack(spacing: 3) {
            completionButton(for: task, displayedDay: displayedDay, height: height)
            if family == .systemSmall {
                taskTitle(task.title)
            } else {
                Link(destination: FlowWidgetRoute.url(for: task.id)) { taskTitle(task.title) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height)
        .padding(.trailing, 4)
        .background(renderingMode == .fullColor ? Color.white : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6))
    }

    private func taskTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: family == .systemSmall ? 10 : 11, weight: .medium))
            .foregroundStyle(ink)
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .privacySensitive()
    }

    @ViewBuilder
    private func completionButton(for task: FlowWidgetDay.Task, displayedDay: Date, height: CGFloat) -> some View {
        if #available(iOS 17.0, *), !entry.opensForCompletion, let occurrenceDay = task.occurrenceDay {
            Button(intent: CompleteLifeFlowWidgetTaskIntent(taskID: task.id, occurrenceDay: occurrenceDay,
                                                            displayedDay: displayedDay)) {
                circle(height)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("ToDoを達成")
            .accessibilityIdentifier("widget-complete-task")
        } else if #available(iOS 27.0, *), let occurrenceDay = task.occurrenceDay {
            completionLink(for: task, occurrenceDay: occurrenceDay, displayedDay: displayedDay, height: height)
        } else if family != .systemSmall, let occurrenceDay = task.occurrenceDay {
            completionLink(for: task, occurrenceDay: occurrenceDay, displayedDay: displayedDay, height: height)
        } else {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ink)
                .frame(width: 24, height: height)
                .accessibilityHidden(true)
        }
    }

    private func completionLink(for task: FlowWidgetDay.Task, occurrenceDay: Date,
                                displayedDay: Date, height: CGFloat) -> some View {
        Link(destination: FlowWidgetRoute.completionURL(for: task.id, occurrenceDay: occurrenceDay,
                                                       displayedDay: displayedDay)) {
            circle(height)
        }
        .accessibilityLabel("ToDoを達成してLifeFlowを開く")
    }

    private func circle(_ height: CGFloat) -> some View {
        Image(systemName: "circle")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(renderingMode == .fullColor ? accent : ink)
            .frame(width: 40, height: height)
            .contentShape(Rectangle())
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
        .contentMarginsDisabled()
    }
}
