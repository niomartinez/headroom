import Foundation
import os

/// App-scoped security-scoped bookmarks for granted folders, kept in UserDefaults (spec §4).
@MainActor
struct BookmarkStore {
    /// A resolved grant. `url` is being accessed; balance with `stopAccessingSecurityScopedResource()`.
    struct Grant {
        let url: URL
    }

    let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.niomartinez.headroom", category: "access")

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Resolves the saved bookmark and starts accessing it. Refreshes a stale bookmark; forgets one
    /// that no longer resolves (folder deleted or moved), so the UI asks again.
    func restore(_ folder: HeadroomFolder) -> Grant? {
        guard let data = defaults.data(forKey: folder.bookmarkKey) else { return nil }
        var isStale = false
        let url: URL
        do {
            url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale)
        } catch {
            logger.error("Forgetting unresolvable bookmark for \(folder.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            forget(folder)
            return nil
        }
        guard url.startAccessingSecurityScopedResource() else {
            logger.error("Forgetting bookmark for \(folder.rawValue, privacy: .public): access was refused")
            forget(folder)
            return nil
        }
        if isStale {
            do {
                try save(url, for: folder)
            } catch {
                logger.error("Couldn't refresh stale bookmark for \(folder.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return Grant(url: url)
    }

    /// Saves a bookmark for a folder the user just picked (or re-saves a stale one).
    func save(_ url: URL, for folder: HeadroomFolder) throws {
        var options: URL.BookmarkCreationOptions = [.withSecurityScope]
        if folder.isReadOnly {
            options.insert(.securityScopeAllowOnlyReadAccess)
        }
        let data = try url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(data, forKey: folder.bookmarkKey)
    }

    func forget(_ folder: HeadroomFolder) {
        defaults.removeObject(forKey: folder.bookmarkKey)
    }
}
