import Foundation

public enum SessionRegistryError: Error, Equatable {
    case directoryUnreadable
}

/// Reads the Claude Code session registry, `~/.claude/sessions` (spec §2.2).
public struct SessionRegistryReader: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Every parseable `*.json` entry (unfiltered). A missing directory returns `[]`;
    /// an existing but unreadable one throws `.directoryUnreadable`.
    public func readEntries() throws -> [RegistryEntry] {
        let files: [URL]
        do {
            // `contentsOfDirectory(at:)` refuses a directory that is itself a symlink.
            files = try FileManager.default.contentsOfDirectory(
                at: directory.resolvingSymlinksInPath(),
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        } catch {
            throw SessionRegistryError.directoryUnreadable
        }
        return files
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { JSONObject(contentsOf: $0).flatMap(RegistryEntry.init(json:)) }
    }
}
