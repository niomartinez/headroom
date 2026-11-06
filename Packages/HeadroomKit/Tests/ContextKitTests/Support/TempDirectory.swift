import Foundation

/// Runs `body` with a fresh, empty directory that is removed afterwards.
func withTempDirectory<T>(_ body: (URL) throws -> T) throws -> T {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ContextKitTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: url) }
    return try body(url)
}

extension URL {
    /// Creates (or replaces) the file at this URL with `text`, creating parent directories.
    func write(_ text: String) throws {
        try FileManager.default.createDirectory(at: deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: self)
    }

    func append(_ text: String) throws {
        let handle = try FileHandle(forWritingTo: self)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    var fileSize: Int {
        (try? resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
    }
}
