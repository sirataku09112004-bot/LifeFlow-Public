import Foundation

struct FlowCheckIn {
    let day: Date
    let fireDate: Date

    var identifier: String { Self.identifier(for: day) }

    static func identifier(for day: Date) -> String {
        "lifeflow.check-in.\(Int(day.timeIntervalSince1970))"
    }

    static func plan(now: Date, lastOpened: Date?, minuteOfDay: Int, clock: FlowClock, available: Int) -> [Self] {
        guard (240...1439).contains(minuteOfDay), available > 0 else { return [] }
        let today = clock.today(now)
        let lastDay = lastOpened.map { clock.today($0) }
        return (0..<14).compactMap { offset -> Self? in
            guard let day = clock.calendar.date(byAdding: .day, value: offset, to: today),
                  day != lastDay,
                  let fire = clock.calendar.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: day),
                  fire > now else { return nil }
            return Self(day: day, fireDate: fire)
        }.prefix(available).map { $0 }
    }
}
