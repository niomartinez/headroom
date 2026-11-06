import Foundation

/// Telling a session's process apart from a later, unrelated process that was given the same pid
/// (spec §2.2, §2.5). A crashed or SIGKILLed session leaves its files behind, and `kill(pid, 0)`
/// alone would take whatever now holds the pid for that session.
enum ProcessStart {
    /// One second because the recorded times are whole seconds (`procStart`, the bridge's `ts`),
    /// plus one second of clock slack.
    static let tolerance: TimeInterval = 2

    /// Whether a process that started at `started` is the one whose `procStart` is `recorded`.
    static func matches(_ started: Date, recorded: Date) -> Bool {
        abs(started.timeIntervalSince(recorded)) < tolerance
    }

    /// Whether a process that started at `started` can have written a record last written at
    /// `written`: the writer was running then, so it started earlier.
    static func canHaveWritten(started: Date, at written: Date) -> Bool {
        started.timeIntervalSince(written) < tolerance
    }

    /// Reads `procStart` as Claude Code writes it: `LC_ALL=C TZ=UTC ps -o lstart= -p <pid>`, which
    /// is `%a %b %e %H:%M:%S %Y` in UTC (`Thu Sep 24 10:06:01 2026`, `Thu Sep  3 16:27:07 2026`).
    /// Anything else is nil: no guessing at other formats or time zones.
    static func parseLstart(_ text: String?) -> Date? {
        guard let fields = text?.split(whereSeparator: \.isWhitespace), fields.count == 5,
              weekdays.contains(String(fields[0])),
              let month = months.firstIndex(of: String(fields[1])).map({ $0 + 1 }),
              let day = number(fields[2], digits: 1...2),
              let year = number(fields[4], digits: 4...4)
        else { return nil }

        let time = fields[3].split(separator: ":", omittingEmptySubsequences: false)
        guard time.count == 3,
              let hour = number(time[0], digits: 2...2), hour < 24,
              let minute = number(time[1], digits: 2...2), minute < 60,
              let second = number(time[2], digits: 2...2), second < 60
        else { return nil }

        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        // `date(from:)` rolls Sep 31 over to Oct 1; a date that does not round-trip is not one.
        guard let date = utcCalendar.date(from: components),
              utcCalendar.dateComponents([.year, .month, .day], from: date)
                == DateComponents(year: year, month: month, day: day)
        else { return nil }
        return date
    }

    private static let weekdays: Set<String> = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    /// A number written with only ASCII digits, as many as `digits` allows.
    private static func number(_ text: Substring, digits: ClosedRange<Int>) -> Int? {
        guard digits.contains(text.count), text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(text)
    }
}
