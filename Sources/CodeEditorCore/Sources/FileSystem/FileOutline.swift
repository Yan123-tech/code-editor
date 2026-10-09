import Foundation

/// Flattening an expanded directory tree into displayable rows.
///
/// Extracted from the sidebar view so the traversal — depth cap, expansion
/// recursion, directory-first ordering — is testable without a window server.
/// Only expanded branches are enumerated, so a large workspace costs nothing
/// until it is opened.
public enum FileOutline {
    /// A single visible row: the item plus how deep it sits in the expanded tree.
    public struct Row: Identifiable, Sendable, Equatable {
        public let item: FileSystemItem
        public let depth: Int

        public var id: URL { item.url }

        public init(item: FileSystemItem, depth: Int) {
            self.item = item
            self.depth = depth
        }
    }

    /// Flatten `directory` recursively.
    ///
    /// - Parameters:
    ///   - children: returns the sorted children of a directory.
    ///   - isExpanded: whether a directory's children should be included.
    ///   - depthLimit: a hard cap that guards against symlink cycles. The cap is a
    ///     depth, not a node count, so it cannot be exhausted by a wide tree.
    public static func rows(
        from directory: URL,
        children: (URL) -> [FileSystemItem],
        isExpanded: (URL) -> Bool,
        depthLimit: Int = 32
    ) -> [Row] {
        func walk(_ directory: URL, depth: Int, remaining: Int) -> [Row] {
            guard remaining > 0 else { return [] }

            var result: [Row] = []
            for item in children(directory) {
                result.append(Row(item: item, depth: depth))
                if item.isDirectory, isExpanded(item.url) {
                    result.append(
                        contentsOf: walk(item.url, depth: depth + 1, remaining: remaining - 1)
                    )
                }
            }
            return result
        }

        return walk(directory, depth: 0, remaining: depthLimit)
    }
}
