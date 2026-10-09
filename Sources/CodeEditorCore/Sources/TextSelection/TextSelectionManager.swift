import Foundation

/// Manages the set of selections for a document, including multi-cursor.
@MainActor
@Observable
public final class TextSelectionManager {
    /// All active selections; never empty, the first is the primary one.
    public private(set) var selections: [TextSelection] = [TextSelection()]

    /// The primary selection.
    public var primarySelection: TextSelection {
        selections[0]
    }

    public var hasMultipleSelections: Bool {
        selections.count > 1
    }

    /// True when every selection is just a cursor (no text highlighted).
    public var hasOnlyCursors: Bool {
        selections.allSatisfy(\.isEmpty)
    }

    public init() {}

    // MARK: - Mutation

    public func setSelection(_ selection: TextSelection) {
        setSelection(from: selection.start, to: selection.end)
    }

    public func setSelection(location: Int) {
        setSelection(from: location, to: location)
    }

    public func setSelection(from start: Int, to end: Int) {
        selections[0] = TextSelection(start: start, end: end)
    }

    public func addSelection(_ selection: TextSelection) {
        guard !selections.contains(selection) else { return }
        selections.append(selection)
    }

    public func removeSelection(_ selection: TextSelection) {
        guard selections.count > 1 else { return }
        selections.removeAll { $0 == selection }
    }

    public func clearSelections() {
        selections = [TextSelection()]
    }

    // MARK: - Queries

    /// The text covered by all selections, in document order.
    public func selectedText(in content: String) -> String {
        let string = content as NSString
        return selections
            .sorted { $0.start < $1.start }
            .compactMap { selection -> String? in
                let range = selection.nsRange
                guard range.location >= 0, NSMaxRange(range) <= string.length else { return nil }
                return string.substring(with: range)
            }
            .joined()
    }

    /// Line numbers touched by the primary selection, used to highlight the gutter.
    public func selectedLines(in document: Document) -> Set<Int> {
        guard let start = document.lineAndColumn(for: primarySelection.start),
              let end = document.lineAndColumn(for: primarySelection.end) else { return [] }
        return Set(start.line...end.line)
    }
}