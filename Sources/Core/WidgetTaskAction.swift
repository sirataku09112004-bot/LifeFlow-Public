import Foundation

enum FlowWidgetTaskAction {
    static func complete(_ taskID: UUID, occurrenceDay: Date, displayedDay: Date? = nil, data: FlowData,
                         now: Date, clock: FlowClock) -> FlowData? {
        // The widget may still show yesterday's timeline after the 04:00 boundary.
        if let displayedDay, displayedDay != clock.today(now) { return nil }
        var updated = data
        guard updated.rollover(now: now, clock: clock, maxCarries: 10_000) else { return nil }
        let list = FlowTaskList(tasks: updated.tasks, query: "", now: now, clock: clock,
                                todayOrder: updated.todayOrder ?? [])
        guard let task = list.today.first(where: {
            $0.id == taskID && clock.day($0.day) == clock.day(occurrenceDay)
        }) else { return nil }
        switch updated.resolveDisplayedTask(task, outcome: .completed, now: now, clock: clock,
                                            maxCarries: 10_000) {
        case .resolved:
            return updated
        case .stale, .blocked, .rolloverLimit:
            return nil
        }
    }
}

#if os(iOS)
enum FlowWidgetSharedDataFile {
    private static let maxDataBytes = 20 * 1024 * 1024

    static func readData(from url: URL) throws -> Data {
        var result: Result<Data, Error>?
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [],
                                                        error: &coordinationError) { coordinatedURL in
            result = Result { try Data(contentsOf: coordinatedURL) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        let bytes = try result.get()
        guard bytes.count <= maxDataBytes else { throw FlowError.invalidBackup }
        return bytes
    }

    static func writeData(_ bytes: Data, to url: URL, sharedGroup: Bool) throws {
        guard bytes.count <= maxDataBytes else { throw FlowError.invalidBackup }
        var writeError: Error?
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing,
                                                         error: &coordinationError) { coordinatedURL in
            do {
                try bytes.write(to: coordinatedURL, options: .atomic)
                let protection: FileProtectionType = sharedGroup
                    ? .completeUntilFirstUserAuthentication
                    : .complete
                try FileManager.default.setAttributes([.protectionKey: protection],
                                                      ofItemAtPath: coordinatedURL.path)
            } catch {
                writeError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }
}
#endif
