import Foundation

/// `FinishedTracker.finished` as UserDefaults stores it: session id → seconds since 1970. Only ids and times; never
/// names or paths.
enum FinishedMarks {
    static func encode(_ finished: [String: Date]) -> [String: Double] {
        finished.mapValues(\.timeIntervalSince1970)
    }

    /// Entries that aren't well-formed are skipped; anything else (nil, another type) reads as no marks.
    static func decode(_ value: [String: Any]?) -> [String: Date] {
        var finished: [String: Date] = [:]
        for (id, at) in value ?? [:] {
            guard !id.isEmpty, let seconds = (at as? NSNumber)?.doubleValue, seconds.isFinite else { continue }
            finished[id] = Date(timeIntervalSince1970: seconds)
        }
        return finished
    }
}
