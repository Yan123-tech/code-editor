import Foundation

extension Document {
    /// LSP position (0-indexed line; 0-indexed character in UTF-16 code units) for a UTF-8
    /// content offset.
    ///
    /// `lineAndColumn(for:)` works in UTF-8 bytes; LSP wants UTF-16 code units for
    /// `character`. They coincide for ASCII source, which covers every identifier the
    /// completion popup is offered on. Non-ASCII content (e.g. accented letters in strings)
    /// is a known v1 limitation.
    public func lspPosition(for offset: Int) -> (line: Int, character: Int)? {
        guard let (line, column) = lineAndColumn(for: offset),
            lines.indices.contains(line)
        else { return nil }
        let lineText = lines[line]
        let utf16 = lineText.prefix(column).utf16.count
        return (line, utf16)
    }

    /// The contiguous run of identifier characters (letters, digits, `_`) ending at
    /// `offset` — the text the user is mid-word typing. Returned as a UTF-16 range (the
    /// unit the text view addresses by); `nil` when no identifier character sits
    /// immediately before `offset`.
    ///
    /// `offset` is a UTF-8 offset treated as a UTF-16 index here; for ASCII source these
    /// are the same value, which is the contract honoured throughout the completion path.
    public func completionPrefixRange(at offset: Int) -> NSRange? {
        let source = content
        guard offset > 0, offset <= source.utf16.count else { return nil }
        var start = offset
        while start > 0 {
            let index = source.index(source.startIndex, offsetBy: start - 1)
            let char = source[index]
            if char.isASCII, char.isNumber || char.isLetter || String(char) == "_" {
                start -= 1
            } else {
                break
            }
        }
        return start < offset ? NSRange(location: start, length: offset - start) : nil
    }

    /// The prefix the user is typing at `offset`, for fuzzy filtering of completions.
    public func completionPrefix(at offset: Int) -> String {
        guard let range = completionPrefixRange(at: offset) else { return "" }
        return (content as NSString).substring(with: range)
    }
}
