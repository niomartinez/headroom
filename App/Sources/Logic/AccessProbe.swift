import Darwin
import Foundation

/// Checks whether the process can actually read a Claude folder right now.
enum AccessProbe {
    /// An existing directory (symlinks followed) the process may list and enter.
    static func isReadableDirectory(_ url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            var info = stat()
            guard stat(path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { return false }
            return access(path, R_OK | X_OK) == 0
        }
    }

    /// `true` only when nothing exists at `url` (symlinks followed): `stat` fails with ENOENT. The
    /// sandbox answers that without a grant (an ungranted `~/.claude` stats fine and only refuses
    /// `access`), so a missing folder can be told apart from one that isn't granted. Any other
    /// failure (EPERM, EACCES, a hung mount timing out) counts as present, so the user is still asked.
    static func isMissing(_ url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            var info = stat()
            return stat(path, &info) != 0 && errno == ENOENT
        }
    }
}
