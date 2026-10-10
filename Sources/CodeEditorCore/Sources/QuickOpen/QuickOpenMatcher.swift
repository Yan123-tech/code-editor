import Foundation

// MARK: - QuickOpenMatch

/// One scored candidate from a quick-open search.
///
/// `highlightRanges` are UTF-16 offset ranges into `relativePath`, matching
/// `NSAttributedString`/`AttributedString` semantics, so the view can emphasise
/// the matched characters without re-deriving them.
public struct QuickOpenMatch: Equatable, Sendable {
    public let url: URL
    public let relativePath: String
    public let score: Int
    public let highlightRanges: [Range<Int>]

    public init(url: URL, relativePath: String, score: Int, highlightRanges: [Range<Int>]) {
        self.url = url
        self.relativePath = relativePath
        self.score = score
        self.highlightRanges = highlightRanges
    }
}

// MARK: - QuickOpenMatcher

/// Subsequence scoring for quick-open queries.
///
/// A query matches when its characters appear in the candidate path in order,
/// case- and diacritic-insensitively. Scoring then prefers, in rough order of
/// weight: matches inside the file name over matches in the directories,
/// matches at the start of a path segment, runs of consecutive characters, and
/// shorter paths over longer ones.
///
/// Matching is greedy-earliest: each query character consumes the next
/// occurrence in the path. That is not the globally optimal assignment, but it
/// is deterministic, cheap, and testable — properties a keystroke-time scorer
/// needs more than the last few points of ranking quality.
public enum QuickOpenMatcher {
    /// Score `query` against `relativePath`. Returns nil when the query is empty
    /// or is not a subsequence of the path.
    public static func score(query: String, relativePath: String, url: URL) -> QuickOpenMatch? {
        guard !query.isEmpty else { return nil }

        let pathCharacters = Array(relativePath)
        let foldedPath = pathCharacters.map { fold(String($0)) }
        let foldedQuery = Array(query).map { fold(String($0)) }

        // Greedy-earliest subsequence over the folded characters.
        var positions: [Int] = []
        positions.reserveCapacity(foldedQuery.count)
        var cursor = 0
        for wanted in foldedQuery where !wanted.isEmpty {
            var found: Int?
            var index = cursor
            while index < foldedPath.count {
                if foldedPath[index] == wanted {
                    found = index
                    break
                }
                index += 1
            }
            guard let position = found else { return nil }
            positions.append(position)
            cursor = position + 1
        }

        return QuickOpenMatch(
            url: url,
            relativePath: relativePath,
            score: score(positions: positions, in: pathCharacters),
            highlightRanges: highlightRanges(positions: positions, in: pathCharacters)
        )
    }

    // MARK: - Scoring

    private enum Weight {
        static let perMatch = 10
        static let consecutive = 12
        static let segmentStart = 14
        static let afterSeparator = 8
        static let inFilename = 6
        static let filenameClutter = 1
        static let pathLength = 1
        static let clutterCap = 8
    }

    private static func score(positions: [Int], in characters: [Character]) -> Int {
        let filenameStart = characters.lastIndex(of: "/").map { $0 + 1 } ?? 0
        var total = 0
        var matchedInFilename = 0

        for (ordinal, position) in positions.enumerated() {
            total += Weight.perMatch

            if ordinal > 0, position == positions[ordinal - 1] + 1 {
                total += Weight.consecutive
            }

            if position == 0 || characters[position - 1] == "/" {
                total += Weight.segmentStart
            } else if "/._- ".contains(characters[position - 1]) {
                total += Weight.afterSeparator
            }

            if position >= filenameStart {
                total += Weight.inFilename
                matchedInFilename += 1
            }
        }

        // Unmatched characters in the file name dilute the match.
        let filenameLength = characters.count - filenameStart
        let clutter = max(0, filenameLength - matchedInFilename)
        total -= min(Weight.clutterCap, clutter * Weight.filenameClutter)

        // Shorter paths read as more direct; a small tie-breaker.
        total -= characters.count / 8

        return total
    }

    /// UTF-16 offset ranges of the matched characters in the original string.
    private static func highlightRanges(positions: [Int], in characters: [Character]) -> [Range<Int>] {
        var offsets: [Int] = []
        offsets.reserveCapacity(characters.count + 1)
        var running: Int = 0
        for character in characters {
            offsets.append(running)
            running += String(character).utf16.count
        }
        offsets.append(running)

        return positions.map { offsets[$0]..<offsets[$0 + 1] }
    }

    /// Case- and diacritic-insensitive fold of a single character. Length-stable
    /// per character, so positions always map back to the original string.
    private static func fold(_ character: String) -> String {
        character.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
