import Foundation

// MARK: - RecentProject

/// Represents a recently opened workspace folder.
public struct RecentProject: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String { url.standardizedFileURL.path }
    public let url: URL
    public let name: String
    public let lastOpened: Date

    public init(url: URL, name: String? = nil, lastOpened: Date = Date()) {
        self.url = url
        self.name = name ?? (url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent)
        self.lastOpened = lastOpened
    }
}

// MARK: - RecentProjectsStore

/// Persists recently opened workspace projects in UserDefaults.
public enum RecentProjectsStore {
    private static let key = "CodeEditor.recentProjects"
    public static let maxRecents = 15

    /// Load the list of recent projects, filtering out paths that no longer exist on disk.
    public static func load(defaults: UserDefaults = .standard) -> [RecentProject] {
        guard let data = defaults.data(forKey: key),
              let projects = try? JSONDecoder().decode([RecentProject].self, from: data)
        else {
            return []
        }
        return projects.filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }

    /// Record a workspace URL as opened, placing it at the front of the MRU list.
    public static func record(url: URL, defaults: UserDefaults = .standard) {
        var recents = load(defaults: defaults)
        let standardized = url.standardizedFileURL
        recents.removeAll { $0.url.standardizedFileURL == standardized }
        let entry = RecentProject(url: standardized, name: standardized.lastPathComponent, lastOpened: Date())
        recents.insert(entry, at: 0)
        if recents.count > maxRecents {
            recents = Array(recents.prefix(maxRecents))
        }
        save(recents, defaults: defaults)
    }

    /// Remove a specific workspace from the recent list.
    public static func remove(url: URL, defaults: UserDefaults = .standard) {
        var recents = load(defaults: defaults)
        let standardized = url.standardizedFileURL
        recents.removeAll { $0.url.standardizedFileURL == standardized }
        save(recents, defaults: defaults)
    }

    /// Clear all recent projects.
    public static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }

    /// Persist the list of recent projects.
    public static func save(_ projects: [RecentProject], defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        defaults.set(data, forKey: key)
    }
}
