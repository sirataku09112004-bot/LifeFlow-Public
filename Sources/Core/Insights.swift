import Foundation

struct FlowDaySummary: Identifiable {
    var id: Date { day }
    let day: Date
    var completed = 0
    var failed = 0
    var attempts: Int { completed + failed }
    var rate: Double? { attempts == 0 ? nil : Double(completed) / Double(attempts) }
}
enum FlowInsights {
    // Bucket by the time the user acted, with the same 04:00 cutoff as Today.
    static func days(history: [FlowEvent], count: Int, now: Date, clock: FlowClock) -> [FlowDaySummary] {
        guard count > 0 else { return [] }
        let today = clock.today(now)
        var days = (0..<count).compactMap { offset -> FlowDaySummary? in
            guard let day = clock.calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return FlowDaySummary(day: day)
        }
        let indexes = Dictionary(uniqueKeysWithValues: days.enumerated().map { ($0.element.day, $0.offset) })
        for event in history {
            guard let i = indexes[clock.today(event.recordedAt)] else { continue }
            switch event.outcome {
            case .completed: days[i].completed += 1
            case .failed: days[i].failed += 1
            case .carried, .deleted: break
            }
        }
        return days
    }
}

