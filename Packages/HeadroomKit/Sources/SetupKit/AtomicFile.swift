import Darwin
import Foundation

/// Whole-file writes that readers never see half done: a temp file in the same directory
/// (created with its final permissions, so secrets in settings.json are never briefly
/// readable by others), then `rename(2)` over the destination.
enum AtomicFile {
    struct Failure: Error, CustomStringConvertible {
        var description: String
    }

    static func write(_ data: Data, to url: URL, permissions: mode_t) throws {
        let temp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).headroom-\(UUID().uuidString).tmp")
        let fd = open(temp.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, permissions)
        guard fd >= 0 else { throw failure("create", temp) }
        var error: Failure?
        if fchmod(fd, permissions) != 0 {
            error = failure("set permissions on", temp)
        } else if !writeAll(data, to: fd) {
            error = failure("write", temp)
        }
        if close(fd) != 0, error == nil {
            error = failure("close", temp)
        }
        if error == nil, rename(temp.path, url.path) != 0 {
            error = failure("replace", url)
        }
        if let error {
            unlink(temp.path)
            throw error
        }
    }

    private static func writeAll(_ data: Data, to fd: Int32) -> Bool {
        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return true }
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(fd, base + offset, buffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                offset += written
            }
            return true
        }
    }

    private static func failure(_ action: String, _ url: URL) -> Failure {
        Failure(description: "can't \(action) \(url.lastPathComponent): \(String(cString: strerror(errno)))")
    }
}
