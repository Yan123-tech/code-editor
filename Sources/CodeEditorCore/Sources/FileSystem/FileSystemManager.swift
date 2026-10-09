import Foundation

// MARK: - FileSystemProvider

/// Protocol for file system operations to enable testing and different implementations.
public protocol FileSystemProvider: Sendable {
    func contentsOfDirectory(at url: URL) throws -> [URL]
    func fileExists(at url: URL) -> Bool
    func isDirectory(at url: URL) -> Bool
    func createDirectory(at url: URL) throws
    func createFile(at url: URL, contents: Data) throws
    func removeItem(at url: URL) throws
    func moveItem(at srcURL: URL, to dstURL: URL) throws
    func readFile(at url: URL) throws -> Data
    func writeFile(at url: URL, data: Data) throws
    func attributesOfItem(at url: URL) throws -> [FileAttributeKey: Any]
}

/// Default implementation using `FileManager`.
public struct DefaultFileSystemProvider: FileSystemProvider {
    public init() {}

    public func contentsOfDirectory(at url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsSubdirectoryDescendants]
        )
    }

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func isDirectory(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return isDirectory.boolValue
    }

    public func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func createFile(at url: URL, contents: Data) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: contents) else {
            throw FileSystemError.failedToCreateFile(url)
        }
    }

    public func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    public func moveItem(at srcURL: URL, to dstURL: URL) throws {
        try FileManager.default.moveItem(at: srcURL, to: dstURL)
    }

    public func readFile(at url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            throw FileSystemError.failedToReadFile(url)
        }
    }

    public func writeFile(at url: URL, data: Data) throws {
        do {
            try data.write(to: url)
        } catch {
            throw FileSystemError.failedToWriteFile(url)
        }
    }

    public func attributesOfItem(at url: URL) throws -> [FileAttributeKey: Any] {
        try FileManager.default.attributesOfItem(atPath: url.path)
    }
}

// MARK: - Errors

public enum FileSystemError: LocalizedError {
    case failedToCreateFile(URL)
    case failedToReadFile(URL)
    case failedToWriteFile(URL)
    case notADirectory(URL)
    case itemNotFound(URL)

    public var errorDescription: String? {
        switch self {
        case .failedToCreateFile(let url):
            "Could not create \(url.lastPathComponent)."
        case .failedToReadFile(let url):
            "Could not read \(url.lastPathComponent)."
        case .failedToWriteFile(let url):
            "Could not write \(url.lastPathComponent)."
        case .notADirectory(let url):
            "\(url.lastPathComponent) is not a directory."
        case .itemNotFound(let url):
            "\(url.lastPathComponent) no longer exists."
        }
    }
}

// MARK: - FileSystemItem

/// A file or directory in the file system.
public struct FileSystemItem: Identifiable, Equatable, Hashable {
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public let size: Int64
    public let modificationDate: Date
    public let isHidden: Bool

    public var id: URL { url }

    public init(
        url: URL,
        isDirectory: Bool,
        size: Int64 = 0,
        modificationDate: Date = .distantPast,
        isHidden: Bool? = nil
    ) {
        self.url = url
        self.name = url.lastPathComponent
        self.isDirectory = isDirectory
        self.size = size
        self.modificationDate = modificationDate
        self.isHidden = isHidden ?? name.hasPrefix(".")
    }

    public init(url: URL, fileSystemProvider: FileSystemProvider = DefaultFileSystemProvider()) {
        let isDirectory = fileSystemProvider.isDirectory(at: url)
        let attributes = try? fileSystemProvider.attributesOfItem(at: url)
        self.init(
            url: url,
            isDirectory: isDirectory,
            size: (attributes?[.size] as? NSNumber)?.int64Value ?? 0,
            modificationDate: attributes?[.modificationDate] as? Date ?? .distantPast
        )
    }

    public var iconName: String {
        isDirectory ? "folder" : Self.fileIconName(for: url.pathExtension)
    }

    static func fileIconName(for ext: String) -> String {
        switch ext.lowercased() {
        case "swift": return "swift"
        case "js", "jsx", "mjs", "cjs", "ts", "tsx", "json": return "curlybraces"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "md", "markdown": return "doc.richtext"
        case "html", "htm", "xml": return "globe"
        case "css", "scss", "sass": return "paintbrush"
        case "yml", "yaml", "toml", "txt", "cfg", "conf": return "doc.text"
        case "sh", "bash", "zsh": return "terminal"
        case "rs": return "gearshape.2"
        case "go": return "shippingbox"
        case "java", "kt", "kts": return "cup.and.saucer"
        case "c", "h", "cpp", "cc", "cxx", "hpp", "m", "mm": return "c.square"
        case "cs": return "number.square"
        case "rb": return "diamond"
        case "php": return "p.square"
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "heic": return "photo"
        case "mp4", "mov", "avi", "mkv": return "film"
        case "mp3", "wav", "flac", "aiff": return "music.note"
        case "zip", "tar", "gz", "rar", "7z", "bz2": return "doc.zipper"
        case "pdf": return "doc.richtext"
        default: return "doc"
        }
    }
}

// MARK: - FileSystemManager

/// Lazily loads and caches the directory tree rooted at a folder.
///
/// URLs are normalized on the way in and keyed by path internally: `URL` equality treats
/// `/tmp/x` and `/tmp/x/` as different values, which would otherwise produce duplicate
/// cache entries for the same directory.
@MainActor
@Observable
public final class FileSystemManager {
    public private(set) var rootURL: URL?
    public private(set) var childrenByPath: [String: [FileSystemItem]] = [:]
    public private(set) var expandedPaths: Set<String> = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    private let provider: FileSystemProvider
    private var loadingPaths: Set<String> = []

    public init(provider: FileSystemProvider = DefaultFileSystemProvider()) {
        self.provider = provider
    }

    // MARK: - Paths

    /// A stable dictionary key for a URL, ignoring trailing slashes and `.` segments.
    static func pathKey(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    // MARK: - Root

    public func setRoot(_ url: URL) {
        guard provider.fileExists(at: url) else {
            errorMessage = FileSystemError.itemNotFound(url).localizedDescription
            return
        }
        guard provider.isDirectory(at: url) else {
            errorMessage = FileSystemError.notADirectory(url).localizedDescription
            return
        }

        childrenByPath.removeAll()
        expandedPaths.removeAll()
        rootURL = url
        expandedPaths.insert(Self.pathKey(for: url))
        Task { await load(url) }
    }

    public var rootName: String {
        rootURL?.lastPathComponent ?? "No Folder Opened"
    }

    // MARK: - Loading

    public func children(of url: URL) -> [FileSystemItem] {
        childrenByPath[Self.pathKey(for: url)] ?? []
    }

    /// Load the contents of a directory. Concurrent calls for the same directory are ignored.
    public func load(_ url: URL) async {
        let key = Self.pathKey(for: url)
        guard loadingPaths.insert(key).inserted else { return }

        isLoading = true
        defer {
            loadingPaths.remove(key)
            isLoading = childrenByPath.isEmpty
        }

        do {
            let contents = try provider.contentsOfDirectory(at: url)
            let items =
                contents
                .filter { !$0.lastPathComponent.hasPrefix(".") || $0.lastPathComponent == ".gitignore" }
                .map { FileSystemItem(url: $0, fileSystemProvider: provider) }
                .sorted(by: Self.sorted)

            childrenByPath[key] = items
            errorMessage = nil

            // Recurse into folders that are already expanded so they stay populated.
            for item in items where item.isDirectory && expandedPaths.contains(Self.pathKey(for: item.url)) {
                await load(item.url)
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private static func sorted(_ lhs: FileSystemItem, _ rhs: FileSystemItem) -> Bool {
        if lhs.isDirectory != rhs.isDirectory {
            return lhs.isDirectory
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    // MARK: - Expansion

    public func isExpanded(_ url: URL) -> Bool {
        expandedPaths.contains(Self.pathKey(for: url))
    }

    public func toggleExpansion(of item: FileSystemItem) {
        let key = Self.pathKey(for: item.url)
        if expandedPaths.contains(key) {
            expandedPaths.remove(key)
        } else {
            expandedPaths.insert(key)
            Task { await load(item.url) }
        }
    }

    /// Expand every directory between the root and `url`, so `url` is visible in
    /// the tree. A no-op for paths outside the root or for the root itself.
    ///
    /// Ancestors already expanded are not re-read. The final segment is not
    /// expanded — it is the file being revealed.
    public func reveal(_ url: URL) async {
        guard let rootURL else { return }
        let rootKey = Self.pathKey(for: rootURL)
        let targetKey = Self.pathKey(for: url)
        guard targetKey.hasPrefix(rootKey + "/") else { return }

        var current = rootKey
        let segments = targetKey.dropFirst(rootKey.count + 1).split(separator: "/").map(String.init)
        for segment in segments.dropLast() {
            current += "/" + segment
            if expandedPaths.insert(current).inserted {
                await load(URL(fileURLWithPath: current, isDirectory: true))
            }
        }
    }

    /// Dismiss the current error. The view layer calls this when the user closes
    /// the error alert; without it the presenting condition stays true and the
    /// alert re-presents immediately.
    public func clearError() {
        errorMessage = nil
    }

    // MARK: - Mutations

    public func createFile(named name: String, in directory: URL) async throws {
        let url = directory.appendingPathComponent(name)
        guard !provider.fileExists(at: url) else { throw FileSystemError.failedToCreateFile(url) }
        try provider.createFile(at: url, contents: Data())
        await reload(directory)
    }

    public func createFolder(named name: String, in directory: URL) async throws {
        let url = directory.appendingPathComponent(name)
        guard !provider.fileExists(at: url) else { throw FileSystemError.failedToCreateFile(url) }
        try provider.createDirectory(at: url)
        expandedPaths.insert(Self.pathKey(for: url))
        await reload(directory)
    }

    public func rename(_ item: FileSystemItem, to newName: String) async throws {
        let parent = item.url.deletingLastPathComponent()
        let destination = parent.appendingPathComponent(newName)
        try provider.moveItem(at: item.url, to: destination)
        invalidate(item.url)
        await reload(parent)
    }

    public func delete(_ item: FileSystemItem) async throws {
        let parent = item.url.deletingLastPathComponent()
        try provider.removeItem(at: item.url)
        invalidate(item.url)
        await reload(parent)
    }

    /// Drop cached entries for a path that no longer exists under that name, and everything
    /// beneath it.
    private func invalidate(_ url: URL) {
        let key = Self.pathKey(for: url)
        childrenByPath.removeValue(forKey: key)
        expandedPaths.remove(key)
        loadingPaths.remove(key)
        childrenByPath = childrenByPath.filter { !$0.key.hasPrefix(key + "/") }
        expandedPaths = expandedPaths.filter { !$0.hasPrefix(key + "/") }
    }

    /// Force a fresh read of a directory's contents.
    private func reload(_ url: URL) async {
        loadingPaths.remove(Self.pathKey(for: url))
        await load(url)
    }
}
