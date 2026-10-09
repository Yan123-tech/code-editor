import Foundation

// MARK: - SessionSnapshot

/// What the app restores on launch: the workspace root, which files were open,
/// and which was active. Untitled documents have no path and are deliberately
/// absent — they have no stable identity across launches.
public struct SessionSnapshot: Codable, Equatable, Sendable {
    public var rootPath: String?
    public var openPaths: [String]
    public var activePath: String?

    public init(rootPath: String? = nil, openPaths: [String] = [], activePath: String? = nil) {
        self.rootPath = rootPath
        self.openPaths = openPaths
        self.activePath = activePath
    }
}

// MARK: - SessionStore

/// Persists the session snapshot in UserDefaults.
///
/// Paths are stored as plain strings, which is only correct because the app is not
/// sandboxed. Under App Sandbox a path can become stale after relaunch; a sandboxed
/// build would need security-scoped bookmarks here instead. Do not carry this file
/// into a sandboxed target unchanged.
public enum SessionStore {
    private static let key = "CodeEditor.session"

    /// Load the snapshot, if one was saved.
    public static func load(defaults: UserDefaults = .standard) -> SessionSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SessionSnapshot.self, from: data)
    }

    /// Persist the snapshot.
    public static func save(_ snapshot: SessionSnapshot, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    /// Drop the snapshot, for a fresh start on next launch.
    public static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
