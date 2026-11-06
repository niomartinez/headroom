import Darwin
import Foundation

/// Reads files that must be regular files (following symbolic links). Anything else (a FIFO, a
/// socket, a device) is refused without waiting on it: opening or reading a FIFO would block until
/// another process writes to it, and `BridgeInstaller.state()` runs on every refresh.
enum RegularFile {
    struct Contents {
        var data: Data
        var permissions: mode_t
    }

    enum Failure: Error, Equatable {
        /// stat(2), open(2) or read(2) failed with this errno (ENOENT: nothing there).
        case system(Int32)
        case notRegular
        case tooLarge(Int)
    }

    /// The whole file, failing when it holds more than `maxSize` bytes.
    static func read(_ url: URL, maxSize: Int) -> Result<Contents, Failure> {
        withOpenFile(url) { fd, info in
            guard Int(info.st_size) <= maxSize else { return .failure(.tooLarge(Int(info.st_size))) }
            return readAll(fd, limit: maxSize + 1).flatMap { data in
                data.count > maxSize
                    ? .failure(.tooLarge(data.count))
                    : .success(Contents(data: data, permissions: info.st_mode & 0o7777))
            }
        }
    }

    /// At most the first `count` bytes of the file.
    static func prefix(of url: URL, count: Int) -> Result<Data, Failure> {
        withOpenFile(url) { fd, _ in readAll(fd, limit: count) }
    }

    private static func withOpenFile<T>(_ url: URL, _ body: (Int32, stat) -> Result<T, Failure>) -> Result<T, Failure> {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return .failure(.system(errno)) }
        guard info.st_mode & S_IFMT == S_IFREG else { return .failure(.notRegular) }
        // O_NONBLOCK: should the path have been swapped for a FIFO since the stat, open returns at once.
        let fd = open(url.path, O_RDONLY | O_NONBLOCK | O_NOCTTY | O_CLOEXEC)
        guard fd >= 0 else { return .failure(.system(errno)) }
        defer { close(fd) }
        guard fstat(fd, &info) == 0 else { return .failure(.system(errno)) }
        guard info.st_mode & S_IFMT == S_IFREG else { return .failure(.notRegular) }
        return body(fd, info)
    }

    private static func readAll(_ fd: Int32, limit: Int) -> Result<Data, Failure> {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while data.count < limit {
            let wanted = min(buffer.count, limit - data.count)
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, wanted) }
            if count < 0 {
                if errno == EINTR { continue }
                return .failure(.system(errno))
            }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return .success(data)
    }
}
