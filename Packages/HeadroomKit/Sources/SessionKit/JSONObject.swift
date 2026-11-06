import CoreFoundation
import Foundation

/// A parsed JSON object with forgiving, typed accessors: a missing value, `null`, or a value of
/// the wrong type all read as `nil`. Used for untrusted files written by other programs.
struct JSONObject {
    /// Registry and bridge files are a few kilobytes at most; anything past this is not ours.
    static let maxFileBytes = 1 << 20

    private let storage: [String: Any]

    private init(storage: [String: Any]) {
        self.storage = storage
    }

    init?(data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        self.init(storage: object)
    }

    /// Parses a regular file of at most `maxFileBytes`. FIFOs, sockets, directories and symlinks
    /// are refused without opening them, so a stray special file can never block the reader.
    init?(contentsOf url: URL) {
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
              let handle = try? FileHandle(forReadingFrom: url)
        else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Self.maxFileBytes + 1),
              data.count <= Self.maxFileBytes
        else { return nil }
        self.init(data: data)
    }

    /// A non-empty string.
    func string(_ key: String) -> String? {
        guard let value = storage[key] as? String, !value.isEmpty else { return nil }
        return value
    }

    /// A finite number; JSON booleans are not numbers here.
    func number(_ key: String) -> Double? {
        guard let value = storage[key] as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite
        else { return nil }
        return value.doubleValue
    }

    func object(_ key: String) -> JSONObject? {
        (storage[key] as? [String: Any]).map(JSONObject.init(storage:))
    }

    /// A positive whole number that fits a `pid_t`.
    func pid(_ key: String) -> Int32? {
        guard let value = number(key), let pid = Int32(exactly: value), pid > 0 else { return nil }
        return pid
    }

    func integer(_ key: String) -> Int? {
        number(key).flatMap { Int(exactly: $0) }
    }

    func date(epochMilliseconds key: String) -> Date? {
        number(key).map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    func date(epochSeconds key: String) -> Date? {
        number(key).map { Date(timeIntervalSince1970: $0) }
    }
}
