import Foundation

// MARK: - IndexedFile

/// One file known to the quick-open index.
public struct IndexedFile: Equatable, Sendable {
    public let url: URL
    public let relativePath: String

    public init(url: URL, relativePath: String) {
        self.url = url
        self.relativePath = relativePath
    }
}

// MARK: - QuickOpenIndex

/// Walks the workspace for quick-open, off the main actor, in bounded batches.
///
/// The walk skips dependency and build directories — `.git`, `.build`, `build`,
/// `node_modules`, `DerivedData`, `.swiftpm` — and dot-directories generally, and
/// stops at `maxEntries` so a runaway tree cannot wedge the app.
///
/// Re-indexing cancels the previous walk: each batch is published only if it was
/// collected under the current generation, so a stale walk's results are dropped
/// rather than mixed in.
///
/// Scope limitation, deliberate: the index is a filesystem walk, not an FSEvents
/// stream. It refreshes when the workspace root changes or when `reindex` is
/// called; files created after the last walk are not findable until then.
@MainActor
@Observable
public final class QuickOpenIndex {
    public private(set) var entries: [IndexedFile] = []
    public private(set) var isIndexing = false

    private let provider: FileSystemProvider
    private var generation = 0

    /// Directories whose contents are never worth listing.
    private nonisolated static let skippedNames: Set<String> = [
        ".git", ".build", "build", "node_modules", "DerivedData", ".swiftpm", "Pods",
    ]

    private nonisolated static let maxEntries = 20_000
    private nonisolated static let maxDepth = 16

    public init(provider: FileSystemProvider = DefaultFileSystemProvider()) {
        self.provider = provider
    }

    /// Rebuild the index for `root`. The previous walk, if any, is cancelled.
    public func reindex(root: URL) {
        generation += 1
        let current = generation
        entries = []
        isIndexing = true

        let provider = provider
        Task {
            await Self.walk(root: root, provider: provider) { [weak self] batch in
                await MainActor.run {
                    guard let self, self.generation == current else { return false }
                    self.entries.append(contentsOf: batch)
                    return true
                }
            }
            await MainActor.run { [weak self] in
                guard let self, self.generation == current else { return }
                self.isIndexing = false
            }
        }
    }

    /// Top matches for a query, highest score first, ties broken by path length.
    public func search(_ query: String, limit: Int = 20) -> [QuickOpenMatch] {
        guard !query.isEmpty else { return [] }

        var matches: [QuickOpenMatch] = []
        matches.reserveCapacity(min(entries.count, 256))
        for entry in entries {
            if let match = QuickOpenMatcher.score(
                query: query,
                relativePath: entry.relativePath,
                url: entry.url
            ) {
                matches.append(match)
            }
        }

        matches.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.relativePath.count == $1.relativePath.count
                ? $0.relativePath < $1.relativePath
                : $0.relativePath.count < $1.relativePath.count
        }
        return Array(matches.prefix(limit))
    }

    /// Breadth-first walk that yields files in batches. The handler returns false
    /// to cancel — used when a newer generation has taken over.
    private nonisolated static func walk(
        root: URL,
        provider: FileSystemProvider,
        yield: @Sendable ([IndexedFile]) async -> Bool
    ) async {
        var queue: [(url: URL, depth: Int, prefix: String)] = [(root, 0, "")]
        var collected: [IndexedFile] = []
        var cancelled = false

        while !queue.isEmpty, !cancelled, collected.count < maxEntries {
            let (directory, depth, prefix) = queue.removeFirst()
            guard depth < maxDepth else { continue }
            guard let contents = try? provider.contentsOfDirectory(at: directory) else { continue }

            var batch: [IndexedFile] = []
            for item in contents {
                let name = item.lastPathComponent
                if name.hasPrefix(".") { continue }
                if provider.isDirectory(at: item) {
                    guard !skippedNames.contains(name) else { continue }
                    queue.append((item, depth + 1, prefix.isEmpty ? name : prefix + "/" + name))
                } else {
                    batch.append(
                        IndexedFile(
                            url: item,
                            relativePath: prefix.isEmpty ? name : prefix + "/" + name
                        )
                    )
                }
            }

            if !batch.isEmpty {
                collected.append(contentsOf: batch)
                if await yield(batch) == false {
                    cancelled = true
                }
            }
        }
    }
}
