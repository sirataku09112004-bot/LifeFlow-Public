import AppIntents
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
        TodayEntry(date: Date(), day: FlowWidgetDay(day: Date(), remaining: 3, percent: 40, titlesVisible: false,
                                                   tasks: [], undated: .init(remaining: 3, tasks: [])))
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
    var undatedOnly = false
    private var ink: Color {
        renderingMode == .fullColor ? Color(.sRGB, red: 208 / 255, green: 226 / 255, blue: 190 / 255) : .primary
    }
    private let canvas = Color.black
    private var rowBorder: Color { renderingMode == .fullColor ? ink.opacity(0.18) : .clear }

    var body: some View {
        if #available(iOS 17.0, *) {
            content.padding(.horizontal, 7).padding(.vertical, 6)
                .containerBackground(canvas, for: .widget)
        } else {
            content.padding(.horizontal, 7).padding(.vertical, 6).background(canvas)
        }
    }

    private var content: some View {
        GeometryReader { geometry in
            let headerHeight: CGFloat = undatedOnly ? 24 : (family == .systemSmall ? 30 : 36)
            let rowHeight = min(24, max(13, floor((geometry.size.height - headerHeight) / CGFloat(taskLimit))))
            if undatedOnly {
                undatedColumn(rowHeight: rowHeight)
            } else if family == .systemMedium {
                HStack(alignment: .top, spacing: 4) {
                    todayColumn(rowHeight: rowHeight)
                    Rectangle()
                        .fill(ink.opacity(0.16))
                        .frame(width: 1)
                        .accessibilityHidden(true)
                    upcomingColumn(rowHeight: rowHeight)
                }
            } else {
                todayColumn(rowHeight: rowHeight)
            }
        }
        .widgetURL(FlowWidgetRoute.url())
    }

    private var taskLimit: Int {
        if undatedOnly { return FlowWidgetDay.undatedTaskLimit }
        return family == .systemSmall ? FlowWidgetDay.smallTaskLimit : FlowWidgetDay.mediumTaskLimit
    }

    private func columnTitle(_ title: LocalizedStringKey) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
    }

    private func undatedColumn(rowHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            columnTitle("やることリスト")
            if let day = entry.day, let undated = day.undated {
                if undated.remaining == 0 {
                    Text("期限なしのタスクはありません")
                        .font(.caption2)
                } else if day.titlesVisible {
                    ForEach(undated.tasks) { task in
                        taskRow(task, displayedDay: day.day, height: rowHeight)
                    }
                } else {
                    Text("LifeFlowの設定でToDo名を表示できます")
                        .font(.caption2)
                }
            } else {
                Text(entry.sharedStorageAvailable ? "LifeFlowを開いて更新" : "LifeFlowとデータを共有できません")
                    .font(.caption)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func todayColumn(rowHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            columnTitle("今日のToDo")
            if let day = entry.day {
                Text("残り \(day.remaining)件 · \(day.percent)%達成")
                    .font(.system(size: 9))
                    .foregroundStyle(ink)
                if family != .systemSmall {
                    ProgressView(value: Double(day.percent), total: 100)
                        .tint(ink)
                        .frame(height: 4)
                        .accessibilityLabel("今日の達成率 \(day.percent)%")
                }
                if day.titlesVisible {
                    let visibleTasks = Array(day.tasks.prefix(taskLimit))
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

    private func upcomingColumn(rowHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            columnTitle("今後の予定")
            if let day = entry.day, day.titlesVisible {
                if let tasks = day.upcomingTasks, !tasks.isEmpty {
                    ForEach(Array(tasks.prefix(taskLimit))) { task in
                        upcomingRow(task, displayedDay: day.day, height: rowHeight)
                    }
                } else {
                    Text(day.upcomingTasks == nil ? "LifeFlowを開いて更新" : "今後の予定はありません")
                        .font(.caption2)
                        .foregroundStyle(ink)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func upcomingRow(_ task: FlowWidgetDay.Task, displayedDay: Date, height: CGFloat) -> some View {
        HStack(spacing: 2) {
            Link(destination: FlowWidgetRoute.url(for: task.id)) {
                HStack(spacing: 4) {
                    if let date = task.occurrenceDay {
                        Text(date, format: Date.FormatStyle().month(.defaultDigits).day(.defaultDigits)
                            .locale(Locale(identifier: "ja_JP")))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    taskTitle(task.title)
                }
                .padding(.leading, 4)
                .privacySensitive()
            }
            .accessibilityIdentifier("widget-upcoming-task:" + task.title)
            if task.completionBlocked == true {
                circle(height, width: 32)
                    .opacity(0.4)
                    .accessibilityLabel("現在は達成を記録できません")
            } else {
                completionButton(for: task, displayedDay: displayedDay, height: height, trailing: true)
            }
        }
        .frame(height: height)
        .background { RoundedRectangle(cornerRadius: 6).strokeBorder(rowBorder) }
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
        .background { RoundedRectangle(cornerRadius: 6).strokeBorder(rowBorder) }
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
    private func completionButton(for task: FlowWidgetDay.Task, displayedDay: Date, height: CGFloat,
                                  trailing: Bool = false) -> some View {
        let width: CGFloat = trailing ? 32 : 40
        if #available(iOS 17.0, *), !entry.opensForCompletion, let occurrenceDay = task.occurrenceDay {
            Button(intent: CompleteWidgetTaskInAppIntent(taskID: task.id, occurrenceDay: occurrenceDay,
                                                        displayedDay: displayedDay)) {
                circle(height, width: width)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("ToDoを達成")
            .accessibilityIdentifier(trailing ? "widget-complete-upcoming-task" : "widget-complete-task")
        } else if #available(iOS 27.0, *), let occurrenceDay = task.occurrenceDay {
            completionLink(for: task, occurrenceDay: occurrenceDay, displayedDay: displayedDay, height: height, width: width)
        } else if family != .systemSmall, let occurrenceDay = task.occurrenceDay {
            completionLink(for: task, occurrenceDay: occurrenceDay, displayedDay: displayedDay, height: height, width: width)
        } else {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ink)
                .frame(width: 24, height: height)
                .accessibilityHidden(true)
        }
    }

    private func completionLink(for task: FlowWidgetDay.Task, occurrenceDay: Date,
                                displayedDay: Date, height: CGFloat, width: CGFloat) -> some View {
        Link(destination: FlowWidgetRoute.completionURL(for: task.id, occurrenceDay: occurrenceDay,
                                                       displayedDay: displayedDay)) {
            circle(height, width: width)
        }
        .accessibilityLabel("ToDoを達成してLifeFlowを開く")
    }

    private func circle(_ height: CGFloat, width: CGFloat) -> some View {
        Image(systemName: "circle")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(ink)
            .frame(width: width, height: height)
            .contentShape(Rectangle())
    }
}

@main
struct LifeFlowWidgetBundle: WidgetBundle {
    var body: some Widget {
        LifeFlowTodayWidget()
        LifeFlowUndatedWidget()
    }
}

struct LifeFlowUndatedWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: FlowWidgetContainer.undatedKind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry, undatedOnly: true)
        }
        .configurationDisplayName("やることリスト")
        .description("期限を設定していない未完了のToDoを最大7件表示します。")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

struct LifeFlowTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: FlowWidgetContainer.kind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("今日のToDo")
        .description("今日の残り件数、達成率とToDoを表示します。中サイズでは今後の予定も確認できます。")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
