import Foundation
import Testing

@testable import CodeEditorLSP

private func item(
    _ label: String,
    filterText: String? = nil,
    sortText: String? = nil,
    kind: CompletionItemKind? = nil
) -> CompletionItem {
    CompletionItem(label: label, kind: kind, sortText: sortText, filterText: filterText)
}

@Suite("Completion matching")
struct CompletionMatchingTests {
    @Suite("fuzzyMatch")
    struct FuzzyMatch {
        @Test("empty query matches anything")
        func emptyQuery() {
            #expect(fuzzyMatch("", "anything") == true)
            #expect(fuzzyMatch("", "") == true)
        }

        @Test("subsequence match is case-insensitive")
        func subsequence() {
            #expect(fuzzyMatch("fp", "forEachPrefix(_:)") == true)
            #expect(fuzzyMatch("FP", "forEachPrefix(_:)") == true)
            #expect(fuzzyMatch("fxp", "forEachPrefix(_:)") == false)
        }

        @Test("missing characters fail")
        func missingCharacter() {
            #expect(fuzzyMatch("zzz", "forEachPrefix(_:)") == false)
            #expect(fuzzyMatch("abc", "abc") == true)
            #expect(fuzzyMatch("abcd", "abc") == false)
        }

        @Test("filterText is matched, not label, when present")
        func filterTextPreferred() {
            // `filterText` differs from `label`; the label alone would fail this query.
            #expect(fuzzyMatch("idx", item("Index", filterText: "idx").filterLabel))
        }
    }

    @Suite("rankedCompletions")
    struct RankedCompletions {
        @Test("empty query keeps every item")
        func emptyQueryKeepsAll() {
            let ranked = rankedCompletions([item("a"), item("b"), item("c")], query: "")
            #expect(ranked.map(\.label) == ["a", "b", "c"])
        }

        @Test("non-matching items are dropped")
        func filtering() {
            let ranked = rankedCompletions([item("map"), item("flatMap"), item("reduce")], query: "flat")
            #expect(ranked.map(\.label) == ["flatMap"])
        }

        @Test("order by sortText then label")
        func sortTextOrdering() {
            let ranked = rankedCompletions(
                [
                    item("b", sortText: "2"),
                    item("a", sortText: "2"),
                    item("c", sortText: "1"),
                ],
                query: ""
            )
            #expect(ranked.map(\.label) == ["c", "a", "b"])
        }

        @Test("sortText fallback to label when absent")
        func sortTextFallback() {
            let ranked = rankedCompletions([item("map"), item("flatMap")], query: "")
            #expect(ranked.map(\.label) == ["flatMap", "map"])
        }

        @Test("filtering is a subsequence, not a prefix")
        func subsequenceFilter() {
            // "fp" matches "forEachPrefix" (f, then p in "Prefix") but not "map" (no f).
            let ranked = rankedCompletions([item("forEachPrefix"), item("map")], query: "fp")
            #expect(ranked.map(\.label) == ["forEachPrefix"])
        }
    }

    @Suite("completionOrdered")
    struct CompletionOrdered {
        @Test("stable when sortText ties")
        func tieBreakByLabel() {
            let sorted = [item("b", sortText: "1"), item("a", sortText: "1")].sorted(by: completionOrdered)
            #expect(sorted.map(\.label) == ["a", "b"])
        }
    }

    @Suite("CompletionList decoding")
    struct CompletionListDecoding {
        private func decode(_ json: String) throws -> CompletionList {
            try JSONDecoder().decode(CompletionList.self, from: Data(json.utf8))
        }

        @Test("bare array form")
        func bareArray() throws {
            let list = try decode(#"[{"label":"count"},{"label":"isEmpty"}]"#)
            #expect(list.isIncomplete == false)
            #expect(list.items.map(\.label) == ["count", "isEmpty"])
        }

        @Test("object form with isIncomplete")
        func objectForm() throws {
            let list = try decode(#"{"isIncomplete":true,"items":[{"label":"count"}]}"#)
            #expect(list.isIncomplete == true)
            #expect(list.items.map(\.label) == ["count"])
        }

        @Test("object form without isIncomplete")
        func objectFormMissingIncomplete() throws {
            let list = try decode(#"{"items":[{"label":"count"}]}"#)
            #expect(list.isIncomplete == false)
            #expect(list.items.map(\.label) == ["count"])
        }

        @Test("object form tolerates extra fields sourcekit attaches")
        func extraFieldsTolerated() throws {
            // sourcekit-lsp emits `deprecated`, `data`, `kind` etc. as extra fields.
            let json = #"{"items":[{"label":"isEmpty","kind":22,"deprecated":false,"data":{"sessionId":0}}]}"#
            let list = try decode(json)
            #expect(list.items.map(\.label) == ["isEmpty"])
        }
    }
}
