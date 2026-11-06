import Foundation

/// Display names for sessions (spec §2.2, §2.5).
enum SessionNaming {
    static let untitled = "Untitled session"
    static let untitledTerminal = "Terminal session"

    /// The registry's `nameSource` for a name Claude Code made up from the folder (CLI ≥ 2.1.281):
    /// a slug with non-ASCII letters dropped and a random suffix (`hr-e2e-caf-59` for `hr-e2e café`).
    static let derivedNameSource = "derived"

    /// A session title with surrounding whitespace removed, or nil when nothing is left.
    static func title(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// A registry name worth showing: a real title, not one derived from the folder, which the
    /// folder name itself says better (spec §2.5).
    static func registryTitle(_ name: String?, source: String?) -> String? {
        source == derivedNameSource ? nil : title(name)
    }

    /// The last path component of `path` (trailing slashes ignored), or nil for an empty path or `/`.
    static func folderName(_ path: String?) -> String? {
        guard let path else { return nil }
        let last = (path as NSString).lastPathComponent
        return last.isEmpty || last == "/" ? nil : last
    }
}
