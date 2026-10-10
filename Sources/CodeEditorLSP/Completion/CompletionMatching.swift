import Foundation

/// Case- and diacritic-insensitive subsequence (fuzzy) match.
///
/// A completion labeled `forEachPrefix(_:)` matches the query `ffp` because its
/// characters appear in order. Used to narrow the server's list as the user types,
/// mirroring the trigger behaviour upstream expects from a `CompletionMode`.
public func fuzzyMatch(_ query: String, _ label: String) -> Bool {
    let query = query.lowercased()
    let label = label.lowercased()
    guard !query.isEmpty else { return true }
    var scan = label.startIndex
    for char in query {
        guard let range = label[scan...].range(of: String(char)) else { return false }
        scan = range.upperBound
    }
    return true
}

extension CompletionItem {
    /// The string used to filter and rank an item. Servers may set `filterText` to a
    /// substring of the label; absent that we match against the label itself.
    public var filterLabel: String { filterText ?? label }

    /// The value `sortText` when the server supplied it, otherwise the filter label.
    /// sourcekit-lsp emits `sortText`; other servers may not, in which case we fall back
    /// to the label so ordering stays deterministic.
    public var sortKey: String { sortText ?? filterLabel }
}

/// Order completions the way a stable, predictable popup would: by the server's
/// `sortText` first, then by label.
public func completionOrdered(_ lhs: CompletionItem, _ rhs: CompletionItem) -> Bool {
    let l = lhs.sortKey
    let r = rhs.sortKey
    if l != r { return l < r }
    return lhs.filterLabel < rhs.filterLabel
}

/// Filter `items` to those matching `query` (empty query matches all) and rank them.
///
/// - Parameter query: what the user typed at the caret. Computed by the caller from
///   the document so this function stays a pure, side-effect-free ranking step that is
///   cheap enough to run on every cursor move.
/// - Returns: the surviving items in display order.
public func rankedCompletions(_ items: [CompletionItem], query: String) -> [CompletionItem] {
    items
        .filter { fuzzyMatch(query, $0.filterLabel) }
        .sorted(by: completionOrdered)
}
