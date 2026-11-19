import Foundation

enum FlowWidgetTaskAction {
    static func complete(_ taskID: UUID, occurrenceDay: Date, displayedDay: Date? = nil, data: FlowData,
                         now: Date, clock: FlowClock) -> FlowData? {
        // The widget may still show yesterday's timeline after the 04:00 boundary.
        if let displayedDay, displayedDay != clock.today(now) { return nil }
        var updated = data
        guard updated.rollover(now: now, clock: clock, maxCarries: 10_000) else { return nil }
        guard let task = updated.tasks.first(where: {
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

#if os(iOS) || os(macOS)
enum FlowWidgetSharedDataFile {
    private static let maxDataBytes = 20 * 1024 * 1024

    static func readData(from url: URL) throws -> Data {
        guard let bytes = try readIfPresent(from: url) else { throw CocoaError(.fileReadNoSuchFile) }
        return bytes
    }

    static func readIfPresent(from url: URL) throws -> Data? {
        var result: Result<Data?, Error>?
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [],
                                                        error: &coordinationError) { coordinatedURL in
            result = Result { try readUncoordinated(from: coordinatedURL) }
        }
        if let coordinationError {
            if coordinationError.domain == NSCocoaErrorDomain && coordinationError.code == NSFileReadNoSuchFileError {
                return nil
            }
            throw coordinationError
        }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }

    static func encode(_ value: FlowData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    static func decode(_ bytes: Data) throws -> FlowData {
        guard bytes.count <= maxDataBytes else { throw FlowError.invalidBackup }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(FlowData.self, from: bytes).validated()
    }

    static func completeTask(_ id: UUID, occurrenceDay: Date, displayedDay: Date,
                             at url: URL, now: Date, clock: FlowClock) throws -> Bool {
        try updateData(at: url, sharedGroup: true) { bytes in
            guard let bytes else { return nil }
            let data = try decode(bytes)
            guard let completed = FlowWidgetTaskAction.complete(id, occurrenceDay: occurrenceDay,
                                                                displayedDay: displayedDay, data: data,
                                                                now: now, clock: clock) else { return nil }
            return try encode(completed.validated())
        }
    }

    static func writeData(_ bytes: Data, to url: URL, sharedGroup: Bool,
                          beforeWriting: (URL) throws -> Void = { _ in }) throws {
        try coordinateWrite(to: url) { coordinatedURL in
            try beforeWriting(coordinatedURL)
            try saveUncoordinated(bytes, to: coordinatedURL, sharedGroup: sharedGroup)
        }
    }

    /// Keep the read and replacement in the same lock across the app and widget processes.
    /// A nil replacement leaves the original untouched.
    @discardableResult
    static func updateData(at url: URL, sharedGroup: Bool,
                           replace: (Data?) throws -> Data?) throws -> Bool {
        try coordinateWrite(to: url) { coordinatedURL in
            guard let updated = try replace(readUncoordinated(from: coordinatedURL)) else { return false }
            try saveUncoordinated(updated, to: coordinatedURL, sharedGroup: sharedGroup)
            return true
        }
    }

    private static func coordinateWrite<T>(to url: URL, _ body: (URL) throws -> T) throws -> T {
        var result: Result<T, Error>?
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing,
                                                         error: &coordinationError) { coordinatedURL in
            result = Result { try body(coordinatedURL) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        return try result.get()
    }

    private static func readUncoordinated(from url: URL) throws -> Data? {
        do {
            if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maxDataBytes {
                throw FlowError.invalidBackup
            }
            let bytes = try Data(contentsOf: url)
            guard bytes.count <= maxDataBytes else { throw FlowError.invalidBackup }
            return bytes
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return nil
        }
    }

    private static func saveUncoordinated(_ bytes: Data, to url: URL, sharedGroup: Bool) throws {
        guard bytes.count <= maxDataBytes else { throw FlowError.invalidBackup }
        #if os(iOS)
        let protection: Data.WritingOptions = sharedGroup
            ? .completeFileProtectionUntilFirstUserAuthentication : .completeFileProtection
        try bytes.write(to: url, options: [.atomic, protection])
        #else
        try bytes.write(to: url, options: .atomic)
        #endif
    }
}
#endif
