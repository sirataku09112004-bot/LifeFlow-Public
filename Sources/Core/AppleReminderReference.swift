import Foundation

struct FlowAppleReminderReference: Hashable {
    let taskID: UUID
    let occurrenceDay: Date
    let displayedDay: Date

    init(task: FlowTask, displayedDay: Date, clock: FlowClock) {
        taskID = task.id
        occurrenceDay = clock.day(task.day)
        self.displayedDay = displayedDay
    }

    func url(owner: UUID) -> URL {
        URL(string: "lifeflow-reminder://\(owner.uuidString.lowercased())/\(taskID.uuidString)/\(Int(occurrenceDay.timeIntervalSince1970))/\(Int(displayedDay.timeIntervalSince1970))")!
    }

    init?(url: URL?, owner: UUID) {
        guard let url, url.scheme == "lifeflow-reminder", url.host == owner.uuidString.lowercased(),
              url.query == nil, url.fragment == nil else { return nil }
        let path = url.path.split(separator: "/")
        guard path.count == 3, let taskID = UUID(uuidString: String(path[0])),
              let occurrence = Int(path[1]), let displayed = Int(path[2]) else { return nil }
        self.taskID = taskID
        occurrenceDay = Date(timeIntervalSince1970: TimeInterval(occurrence))
        displayedDay = Date(timeIntervalSince1970: TimeInterval(displayed))
    }

    func complete(in data: inout FlowData, at completion: Date?, now: Date, clock: FlowClock) -> Bool {
        // Reminders may provide no timestamp. Only infer it while the original business day is current.
        let recordedAt = completion ?? now
        guard recordedAt <= now, clock.today(recordedAt) == displayedDay,
              let task = data.tasks.first(where: { $0.id == taskID && clock.day($0.day) == occurrenceDay }),
              task.belongsToToday(displayedDay, clock: clock),
              data.resolutionBlock(for: task, now: recordedAt, clock: clock) == nil else { return false }
        return data.resolve(taskID, outcome: .completed, now: recordedAt, clock: clock)
    }
}
