//
//  RecentsPathRepair.swift
//  CodeEdit
//
//  Created by CodeEdit on 10/10/26.
//

import Foundation
import WelcomeWindow

/// Keeps every entry in the welcome window's recent list removable.
///
/// `RecentsStore` keys each bookmark by the path it was recorded under, but "Remove from Recents" matches
/// the path the bookmark *resolves* to. The two differ when the recorded path had a doubled slash
/// (`//Users/…` from `codeedit://file//Users/…`), went through a symlink (`/tmp` → `/private/tmp`), or the
/// file was renamed since; such entries can then never be removed. This rewrites each stored path to the
/// resolved one and drops duplicates that collapse onto the same path, keeping order and bookmark data.
@MainActor
enum RecentsPathRepair {
    /// The `UserDefaults` key `RecentsStore` stores its bookmark entries under.
    private static let bookmarksKey = "recentProjectBookmarks"

    private static var observer: NSObjectProtocol?

    /// Repairs the stored entries now and again after every later change to the recent list.
    static func start() {
        repair()
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: RecentsStore.didUpdateNotification,
            object: nil,
            queue: nil
        ) { _ in
            DispatchQueue.main.async {
                repair()
            }
        }
    }

    /// Rewrites stored paths that differ from where their bookmarks resolve.
    ///
    /// Entries whose bookmark no longer resolves (deleted files, unmounted volumes) are left as they are.
    /// Does nothing if the stored data is not in the expected shape.
    /// - Parameter defaults: The defaults to repair; `nil` uses the ones `RecentsStore` reads from.
    /// - Returns: True if the stored list was changed.
    @discardableResult
    static func repair(defaults: UserDefaults? = nil) -> Bool {
        let defaults = defaults ?? RecentsStore.defaults
        guard let data = defaults.data(forKey: bookmarksKey),
              let entries = try? PropertyListSerialization.propertyList(
                from: data,
                format: nil
              ) as? [[String: Any]] else {
            return false
        }

        var repaired: [[String: Any]] = []
        var seenPaths = Set<String>()
        var changed = false
        for var entry in entries {
            if let storedPath = entry["urlPath"] as? String,
               let bookmark = entry["bookmarkData"] as? Data,
               let resolvedPath = resolvedPath(of: bookmark),
               resolvedPath != storedPath {
                entry["urlPath"] = resolvedPath
                changed = true
            }
            if let path = entry["urlPath"] as? String {
                guard seenPaths.insert(path).inserted else {
                    changed = true
                    continue
                }
            }
            repaired.append(entry)
        }

        guard changed,
              let newData = try? PropertyListSerialization.data(
                fromPropertyList: repaired,
                format: .binary,
                options: 0
              ) else {
            return false
        }
        defaults.set(newData, forKey: bookmarksKey)
        NotificationCenter.default.post(name: RecentsStore.didUpdateNotification, object: nil)
        return true
    }

    /// The path a recent-list bookmark resolves to, resolved the same way `RecentsStore` does.
    private static func resolvedPath(of bookmark: Data) -> String? {
        var isStale = false
        return try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withoutUI, .withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ).path
    }
}
