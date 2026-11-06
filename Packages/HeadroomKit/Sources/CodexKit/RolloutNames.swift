import Foundation

/// A rollout file name: `rollout-<local ts>-<thread uuid>[_<rollout uuid>].jsonl` (1.1 §3.2), matched as the
/// regex `^rollout-(\d{4}-\d\d-\d\dT\d\d-\d\d-\d\d)-([0-9a-f-]{36})(?:_([0-9a-f-]{36}))?\.jsonl$` would, without
/// the regex's cost on every walk. Compressed `.jsonl.zst` history doesn't match: it is ignored.
struct RolloutFileName: Sendable, Equatable {
    /// The thread's id (a UUIDv7), lowercase: the lock file's name and the session id's suffix.
    var threadID: String

    private static let prefix = "rollout-"
    private static let suffix = ".jsonl"
    private static let timestampLength = 19  // 2026-09-20T12-11-17
    private static let uuidLength = 36

    init?(_ name: String) {
        let bytes = Array(name.utf8)
        let prefix = Array(Self.prefix.utf8)
        let suffix = Array(Self.suffix.utf8)
        guard bytes.count >= prefix.count + Self.timestampLength + 1 + Self.uuidLength + suffix.count,
              bytes.starts(with: prefix), bytes.suffix(suffix.count).elementsEqual(suffix)
        else { return nil }
        var index = prefix.count
        guard Self.isTimestamp(bytes[index..<index + Self.timestampLength]) else { return nil }
        index += Self.timestampLength
        guard bytes[index] == UInt8(ascii: "-") else { return nil }
        index += 1
        let thread = bytes[index..<index + Self.uuidLength]
        guard Self.isUUIDText(thread) else { return nil }
        index += Self.uuidLength
        let rest = bytes[index..<(bytes.count - suffix.count)]
        if !rest.isEmpty {
            guard rest.count == 1 + Self.uuidLength, rest.first == UInt8(ascii: "_"),
                  Self.isUUIDText(rest.dropFirst())
            else { return nil }
        }
        threadID = String(decoding: thread, as: UTF8.self)
    }

    /// `\d{4}-\d\d-\d\dT\d\d-\d\d-\d\d`
    private static func isTimestamp(_ bytes: ArraySlice<UInt8>) -> Bool {
        let pattern = Array("dddd-dd-ddTdd-dd-dd".utf8)
        return zip(bytes, pattern).allSatisfy { byte, expected in
            expected == UInt8(ascii: "d") ? (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) : byte == expected
        }
    }

    /// `[0-9a-f-]{36}`
    private static func isUUIDText(_ bytes: ArraySlice<UInt8>) -> Bool {
        bytes.count == uuidLength && bytes.allSatisfy { byte in
            (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
                || byte == UInt8(ascii: "-")
        }
    }
}

enum ThreadID {
    /// When a UUIDv7 thread id was created: its first 48 bits are Unix epoch milliseconds (1.1 §3.2). Nil for
    /// text that isn't a UUID.
    static func creationDate(_ threadID: String) -> Date? {
        let hex = threadID.lowercased().filter { $0 != "-" }
        guard hex.count == 32, hex.allSatisfy(\.isHexDigit), let milliseconds = UInt64(hex.prefix(12), radix: 16) else {
            return nil
        }
        return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1_000)
    }

    /// A lock file's thread id: `<uuid>.lock`, lowercase. Nil for `.coordination.lock` and anything else.
    static func fromLockName(_ name: String) -> String? {
        guard name.hasSuffix(".lock"), !name.hasPrefix(".") else { return nil }
        let id = String(name.dropLast(".lock".count)).lowercased()
        return creationDate(id) == nil ? nil : id
    }
}

/// Codex timestamps: ISO-8601 in UTC with any number of fractional digits (`2026-09-23T13:31:05.698Z`,
/// `…03.145384Z`), or with a `±HH:MM` offset. Parsed by hand: a rollout tail can hold thousands.
enum CodexTime {
    static func parse(_ text: String) -> Date? {
        parse(Array(text.utf8)[...])
    }

    static func parse(_ bytes: ArraySlice<UInt8>) -> Date? {
        let b = Array(bytes)
        guard b.count >= 20 else { return nil }
        func number(_ from: Int, _ count: Int) -> Int? {
            var value = 0
            for i in from..<(from + count) {
                let digit = Int(b[i]) - 48
                guard (0...9).contains(digit) else { return nil }
                value = value * 10 + digit
            }
            return value
        }
        guard let year = number(0, 4), b[4] == UInt8(ascii: "-"), let month = number(5, 2), b[7] == UInt8(ascii: "-"),
              let day = number(8, 2), b[10] == UInt8(ascii: "T") || b[10] == UInt8(ascii: " "),
              let hour = number(11, 2), b[13] == UInt8(ascii: ":"), let minute = number(14, 2),
              b[16] == UInt8(ascii: ":"), let second = number(17, 2),
              (1...12).contains(month), (1...31).contains(day), hour < 24, minute < 60, second < 61
        else { return nil }
        var index = 19
        var fraction = 0.0
        if index < b.count, b[index] == UInt8(ascii: ".") {
            index += 1
            var scale = 0.1
            let digitsStart = index
            while index < b.count, (48...57).contains(b[index]) {
                fraction += Double(b[index] - 48) * scale
                scale /= 10
                index += 1
            }
            guard index > digitsStart else { return nil }
        }
        var offsetSeconds = 0
        guard index < b.count else { return nil }
        switch b[index] {
        case UInt8(ascii: "Z"), UInt8(ascii: "z"):
            index += 1
        case UInt8(ascii: "+"), UInt8(ascii: "-"):
            let sign = b[index] == UInt8(ascii: "+") ? 1 : -1
            guard b.count >= index + 6, let hours = number(index + 1, 2), b[index + 3] == UInt8(ascii: ":"),
                  let minutes = number(index + 4, 2)
            else { return nil }
            offsetSeconds = sign * (hours * 3_600 + minutes * 60)
            index += 6
        default:
            return nil
        }
        guard index == b.count else { return nil }
        let days = daysFromCivil(year: year, month: month, day: day)
        let seconds = days * 86_400 + hour * 3_600 + minute * 60 + second - offsetSeconds
        return Date(timeIntervalSince1970: TimeInterval(seconds) + fraction)
    }

    /// Days since 1970-01-01 in the proleptic Gregorian calendar (Howard Hinnant's algorithm).
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    private static let timestampKey = Array(#""timestamp":""#.utf8)

    /// The top-level `"timestamp"` of a rollout line without decoding it: Codex writes it first, so only the
    /// line's first 128 bytes are searched.
    static func lineTimestamp(_ line: ArraySlice<UInt8>) -> Date? {
        let head = line.prefix(128)
        guard let keyStart = head.firstRange(of: timestampKey)?.upperBound,
              let valueEnd = head[keyStart...].firstIndex(of: UInt8(ascii: "\""))
        else { return nil }
        return parse(head[keyStart..<valueEnd])
    }
}
