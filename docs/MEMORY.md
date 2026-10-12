# Memory

Constraints and facts that are expensive to rediscover. Each entry says what happened, what
it cost, and what to do about it.

**This file is the reason the other documents exist.** If a change makes something here
wrong, fix the file in the same PR.

---

## 1. CI cannot build this package. Do not try to make it.

**The constraint.** `Package.swift` declares `swift-tools-version: 6.4`. No hosted GitHub
runner carries SwiftPM 6.4.

**What was tried, all failing:**

| Attempt | Runner | Toolchain | Result |
|---|---|---|---|
| `xcode-select -s /Applications/Xcode_16.app` | macos-latest | — | `invalid developer directory` — path absent from the image |
| default toolchain | macos-latest | 6.3.3 | manifest 6.4 rejected |
| `setup-xcode` `latest-stable` | macos-15 | 6.2.4 | older still |
| Xcode 26 explicit | macos-26 | 6.3.3 | still short of 6.4 |

**Why lowering the manifest does not work.** Setting `swift-tools-version: 6.3` gets past
SwiftPM, then fails inside a dependency:

```
CodeEditSymbols/CodeEditSymbols.swift:14:42: error: type 'Bundle' has no member 'module'
```

`CodeEditSymbols` 0.2.3 has `Sources/CodeEditSymbols/Symbols.xcassets` but its own
`Package.swift` declares **no** `resources:`. SwiftPM 6.4 infers the bundle and synthesises
`Bundle.module`; 6.3 does not. Every version of that package, 0.1.1 through 0.2.3, has the
same omission — there is no version to pin to.

**Why downgrading the editor does not work.** `CodeEditSourceEditor` gained the
`CodeEditSymbols` dependency at 0.13.0, so 0.12.x avoids it. But 0.12.x requires a
CodeEditTextView 0.10 API that no longer exists:

```
MinimapLineFragmentView.swift:46: error: method does not override any method from its superclass
MinimapLineRenderer.swift:32: error: incorrect argument label in call
```

The 0.11.x line fails the same way on a different API change. There is no working
combination on an old toolchain.

**Current state.** CI runs two jobs that work everywhere:

- **Format** — `swift-format lint --strict`, then `format --in-place` and fail if
  `git diff` is non-empty. `swift-format` ships in the Xcode toolchain, so it is present
  regardless of Swift version.
- **Syntax** — `swiftc -parse` on every file. Parsing does not resolve the dependency graph,
  so it needs no SwiftPM.

Branch protection has **no** required status check, because there is nothing that can pass.

**The cost of this is real.** CI does not catch type errors or failing tests. Every
contributor must run the local gate. Say so in PRs rather than implying CI covered it.

**What unblocks it.** A runner with Xcode 26.4. Then add a `build` job and re-add
`build-and-test` as a required check in one commit.

---

## 2. `swift-format` needs the config or it reports nothing useful

`.swift-format` sets 4-space indentation, 120 columns.

Without it, `swift-format` defaults to 2 spaces and reports **3301** `Indentation` warnings
across 18 files. The real warnings — `OrderedImports`, `DoNotUseSemicolons`, `TrailingComma`
— are invisible in that noise.

With the config: 75 warnings, all real, all fixable. Zero after applying.

Applying the formatter also surfaced two genuine defects the original code had, which
suggests it is worth running before review, not only in CI:

- Semicolon-separated statements in the sidebar context menu
- Unordered import blocks

---

## 3. `URL` equality is not path equality

`URL(fileURLWithPath: "/tmp/x") != URL(fileURLWithPath: "/tmp/x/")`. Same file, different
`absoluteString`.

`FileSystemManager` keys its cache on `url.standardizedFileURL.path` for this reason. Keyed
on `URL`, a rename left the stale entry under the pre-rename key and the sidebar kept
displaying the old filename — the tree appeared to ignore the rename entirely.

Test: `FileSystemManager.cacheKeysIgnoreTrailingSlash`. **Do not simplify it back to `URL`.**

Related trap: `deletingLastPathComponent()` returns a URL *with* a trailing slash. So
`root.appendingPathComponent("x").deletingLastPathComponent() != root` even though the paths
are identical.

---

## 4. The document is the source of truth; the text view binds to it

`SourceEditor` takes a `Binding<String>`. `CodeEditorView` supplies
`Binding(get: { document.content }, set: { document.setContent($0) })`.

There is no push path from `Document` to the text view. That is deliberate: a push model
would need a re-entrancy guard against the text view writing while SwiftUI is mid-update.

**Consequence:** a `Document` mutation originating outside the text view will fight the
binding. Route it through the view. If you add one, you will need to think about this.

`Document` mutations all funnel through one private `apply(_:)`, which recomputes `lines`,
sets `isModified` and notifies the delegate in one place. Keep it that way — the original had
four methods that each did a subset, and the line cache drifted from the content.

---

## 5. `@Observable` and `ObservableObject` are mutually exclusive here

The original `TerminalSession` declared both. That stops `@StateObject` from working — the
type is no longer `ObservableObject`, so `@StateObject` will not accept it, and the error
points at the property wrapper rather than the conformance.

Everything is `@Observable` now. Views hold models via `@State` or `@Bindable`.

Same class of trap: a `@MainActor` class cannot touch its isolated state from `deinit`.
`TerminalSession` has no `deinit`; callers use `disconnect()`.

---

## 6. `Document` is ambiguous with `SwiftUI.Document`

Inside `CodeEditorUI` and `CodeEditorApp`, which import SwiftUI, the bare name `Document`
resolves ambiguously. Use `CodeEditorCore.Document`.

This appears in type positions: parameters, stored properties, `ForEach` element types.
It does *not* shadow value-level uses like `document.content`.

---

## 7. The terminal is pipes, not a PTY

`TerminalSession` spawns `$SHELL -i` with three `Pipe()`s. No job control, no TTY.

Consequences, all expected: `vim` renders wrong, `top` exits immediately, Ctrl-C writes
`0x03` into a pipe the shell does not read as a signal.

This is documented in the type's doc comment and tracked as
[#5](https://github.com/Yan123-tech/code-editor/issues/5). Not an oversight — a PTY layer is C
interop and belongs behind a testable protocol.

---

## 8. CodeEditSourceEditor is pre-1.0 and moves

Pinned `from: "0.15.2"`, so 0.16 lands automatically. That is intentional.

Exposure is contained to three files, all in `Editor/`:

- `EditorTheme+Bridge.swift` — the only place that constructs `EditorTheme.Attribute`
- `CodeEditorView.swift` — `SourceEditor`, `SourceEditorConfiguration` and its nested
  `Appearance` / `Behavior` / `Peripherals`, `InvisibleCharactersConfiguration`,
  `BracketPairEmphasis`
- `EditorState.swift` — `IndentOption` only, because indent is an editor preference

The first two are the deliberate boundary. The third is a thin type reference; if you move
`IndentOption` out of the editor's configuration, that import can go too.

**Keep it at three.** If a fourth file starts naming upstream types, the boundary has
leaked. The count was wrong in the docs for a while — they said two while `EditorState.swift`
had been importing it all along — which is the reason to go and count instead of repeating
the claim.

Known break: 0.8.1 → 0.15 changed the API completely (`CodeEditorSourceEditor` with
`cursorPositions:` became `SourceEditor` with `state: SourceEditorState`), and 0.8.1 no
longer compiles against CodeEditTextView 0.12 at all.

---

## 9. Xcode-build-system leftovers in `.build`

`.build/out/` holds artifacts from an Xcode-driven build, and `swift build` will use
`-D Xcode`. This is stale state from before the package was restructured. If a build behaves
inexplicably, `rm -rf .build` before debugging anything else.

`.build/` is gitignored. `/build` is also ignored because Xcode writes there.

---

## 10. History was rebuilt once

The first published history contained commits that captured stale file contents, caused by a
`git reset --hard` mid-task. The published `main` was reconstructed from scratch and
verified green, so what is on the remote is correct — but part of that work was redone.

The lesson is procedural and it is in [BRANCHING.md](BRANCHING.md): work on feature branches
and merge, rather than rewriting history in place. It is much harder to lose a day's work
that way.

---

## 11. Never derive appearance from colour arithmetic

`ThemeManager.isDark` used to be `currentTheme.background.red < currentTheme.background.blue`.

That returns **false for any neutral background** — `#1e1e1e` is `30 < 30` — so the Dark and
High Contrast palettes forced `.preferredColorScheme(.light)` and every system-drawn control
rendered light against a dark canvas. It looked like a styling problem and was a comparison
operator.

`Theme` now declares `colorScheme` per palette and `isDark` reads it.

Tests: `ThemeManagerTests.appearanceMatchesPalette`, `.neutralBackgroundsAreNotMisread`.
**If you add a palette, set `colorScheme` explicitly.** The initializer defaults it to
`.dark`, which is a silent trap for a new light palette.

---

## 12. A tap gesture inside a selection `List` is swallowed

The sidebar's file tree wanted click-a-row-to-activate. With `List(selection:)` the obvious
`.onTapGesture` on the row **never fires** — the List's own gesture handling consumes the
click, so the row only changed selection and nothing activated.

Activation has to hang off `.onChange(of: selection)`. That is also the Xcode navigator's
behaviour: landing on a file opens it, landing on a folder expands it, and arrowing through
the tree does the same.

Corollary: if the row also carries a button (a disclosure triangle), the button's action and
the selection change both run, so a click toggles twice. Make such controls decorative, or
drive one path only.

Verified by arrowing onto a folder in the running app, not by clicking — synthetic clicks
from System Events do not reach SwiftUI rows, so do not trust them as evidence either way.

---

## 13. `NavigationSplitView` columns are sized in one place

`FileExplorerView` carried `.frame(minWidth:idealWidth:maxWidth:)` on its own root *and* the
split view declared `.navigationSplitViewColumnWidth` on the same column. Two authorities
for one width; the column took whichever won, and the sidebar jumped on relayout.

`.navigationSplitViewColumnWidth` belongs on the column. Nothing inside the column should
also claim a width.

---

## 14. `SessionStore` stores plain paths, which is only valid unsandboxed

`SessionStore` persists `rootPath` and tab paths as strings. That is correct only because
the app is not sandboxed. Under App Sandbox a path can point somewhere useless after
relaunch and the app would restore nothing, silently.

A sandboxed build must store `URL.bookmarkData(includingResourceValuesForKeys:options:)`
and resolve with `startAccessingSecurityScopedResource()`. There is a test at
`SessionStoreTests.roundTrip` that would still pass with bookmarks, so the suite is not the
guard here — this note is.

---

## 15. `.buttonStyle(.prominent)` does not exist on macOS

It is iOS. On macOS the equivalent is `.borderedProminent`. The compiler's "cannot be
resolved without a contextual type" is a poor hint for this; the real problem is the wrong
platform's spelling.

Also: `Button` inside a SwiftUI `Menu` label, and `onExitCommand(perform:)`, both need the
explicit label even when the argument is a bare function reference.

---

## 16. `Scripts/build-app.sh` only fails from a clean checkout

It shipped with `--show-bin-path` on both of its build commands. That flag *locates* the
output directory; it does not build. The script therefore succeeded whenever something else
had already run `swift build`, and failed with

```
install: .build/out/Products/Release/CodeEditorApp: No such file or directory
```

when run from a clean state — pointing at a binary that was never produced.

**Run it from a clean checkout before believing it works:**

```bash
rm -rf build && swift package clean && Scripts/build-app.sh
```

A build step that passes silently when it has nothing to do is worse than no build step.
The same reasoning applies to any script here: if it can succeed while doing nothing, it
will be believed until the one run that needs it.

---

## 17. A caret sits on a line but does not select it

`EditorState` derived `selectedLines` from `start.line...end.line`, which for a collapsed
caret is a one-element set. The status bar then read "1 line selected" on every freshly
opened file — the state was never wrong about the caret, only about what counts as a
selection.

`Document.selectedLines(for:)` now returns an empty set for an empty selection. Callers that
want the caret's line use `lineAndColumn(for:)` instead of inferring it from a selection.

Tests: `Document.collapsedCaretSelectsNothing`, `.selectionReportsCoveredLines`.

Worth remembering as a shape: a summary shown to a user ("3 lines selected") is a claim
about a *state*, not about a *range*. Deriving it from the range without checking whether
the range is degenerate is how you get a readout that is wrong in the one case everybody
sees first.

The same shape bit the session snapshot, and it is worth checking every "restore" feature
against: it persists *paths*, never buffer content. Quit with unsaved changes and the tab
returns showing what is on disk — the edits are gone and nothing said so on the way out.
A feature named "restore" will be read as "resume"; say which one it is, in the docs and
in the UI.

---

## 18. `SourceEditor` never diffs its text on update

`SourceEditor.updateNSViewController` compares language, configuration and highlight
providers. It does **not** compare the text behind its `Binding<String>`. Text is pushed once,
in `makeNSViewController`:

```swift
case .binding(let binding):
    controller.textView.setText(binding.wrappedValue)
```

SwiftUI reuses the view controller, so `make` is not called again when the document changes.
Every tab therefore shows the first file opened, until you switch to a file of a *different
language*, which forces the reload.

**`DocumentTextCoordinator` exists for this and only this.** It captures the controller in
`prepareCoordinator` — the one hook that hands it out — and `CodeEditorView` calls
`reload(text:)` on `document.id` change. It compares against `textView.string` first, so
reloading identical text is free, and `Document.setContent` guards on equality so the
write-back records no edit.

Do not remove it because it looks redundant — it is not, and the symptom is severe enough to
look like a broken app. If upstream 0.16 diffs text on update, delete the coordinator then.

`.id(document.id)` on the editor is the fallback if this ever stops working: correct, but it
rebuilds the tree-sitter highlighter on every tab switch and discards scroll and cursor state.

**No test can catch this.** The defect lives in upstream's view-update logic, not in anything
`CodeEditorCore` owns, so the only check is running the app and opening two files. That check
is now part of the definition of done in [PROCESS.md](PROCESS.md). It found this, a chevron
that stopped working, and a gutter bleeding through the tab strip — after 68 passing tests.

---

## 19. A `Language` identifier that does not match upstream is silence, not a warning

`CodeEditorUI`'s `Language.codeLanguage` resolves highlighting through
`CodeLanguage.detectLanguageFrom`, but `CodeLanguage.editorLanguage` resolves *back*
from the editor's identifier by matching it against `TreeSitterLanguage.rawValue`.
The reverse map is only used by the LSP layer (servers report a `languageId`, which we
turn back into a `Language`), so a mismatched identifier is invisible to highlighting
and only bites when the server talks back.

`shell` ≠ `bash`, `plaintext` ≠ `plainText`, `csharp` ≠ `cSharp`. An identifier with
no upstream grammar silently falls back to plain text — there is no error, the file just
stops being highlighted correctly. `Language.allLanguages` is therefore the single
ordered list, and every static must match a `TreeSitterLanguage` case one-to-one.

Tree-sitter (via `CodeEditLanguages`) ships 42 `TreeSitterLanguage` cases; 8 are not
exposed by this editor (jsdoc, markdownInline, regex, ocaml, agda, goMod, and the two
that overlap). Do not add a static whose identifier has no upstream grammar.

---

## 20. `sourcekit-lsp` server requests use string ids, and its `completion` must be static

`initialize` against `sourcekit-lsp` is followed by `client/registerCapability` requests
**initiated by the server** with **string** ids (`"sk-0"`, `"sk-1"`). `RawMessage` therefore
carries both `id: Int?` (for our outgoing requests) and `stringID: String?` (for server
requests); the transport answers server requests with
`sendResponse(requestID: JSONValue.null)`. Skip those ACKs and `initializeCompletion`/
`documentSymbolProvider` registration stalls — the client reports `isReady = true` but every
follow-on request then hangs until the timeout. This was the second, non-obvious completion
blocker (the first was strict `ServerCapabilities` decoding).

Two more sourcekit quirks to bake in (Xcode 16 toolchain, Swift 6.4.0.34.1):

- With `completion.dynamicRegistration: true` the server registers completion dynamically
  and then emits a ~212KB completion response that is **not valid JSON** — a `textEdit`
  value that is a bare `{<docstring>}`, dangling `"markdown"` tokens, `sortText` carrying a
  docstring. Advertise **static** completion (`dynamicRegistration: false`): the same
  items come back as compact, strictly-valid JSON. `ClientCapabilities.default` sets this.
- As a defensive net, `JSONRPCTransport.repairMalformedJSON` rewrites the single structurally
  invalid shape `:"<...>"}"}` → `:null`. It only ever matches broken JSON, so well-formed
  messages pass through untouched, and it is covered by
  `JSONRPCTransportTests.repairBareStringObject`. It is a fallback, not the primary fix —
  static capabilities keep the response valid in the first place.

E2E: `LSPClientEndToEndTests` is gated on `sourceKitLSPPath` and is local-only (CI can't
launch sourcekit-lsp, see #1). `sourcekit-lsp` is heavy and stalls/OOMs as a child of
`swift test` on the ~200KB `Array`-member response, so the test completes against a tiny
3-member local struct (~1KB response) and retries on a flaky spawn.

## 21. `Position` is UTF-16, 0-indexed, LSP-spec

`LSPClient` converts `Document` offsets to `Position(line:character:)` with UTF-16 code
units and 0-based indices (LSP spec). Off-by-one here silently shifts every completion
anchor, so the edit lands in the wrong place. `DocumentCompletionTests` pins the conversion
for ASCII and for the UTF-16 boundary case.

---

## 22. `URL.resourceValues` is keyed `forKeys:`; `setResourceValues` is mutating

`URL.resourceValues(for: [.contentModificationDateKey])` does not compile — the parameter is
labelled `forKeys:`. The label-less subscript `url.resourceValues[.contentModificationDateKey]`
reads the same way and is easy to confuse for it, which is how I wrote `for:` first.

To fake a future mtime in `DocumentExternalChangeTests`, `URL.setResourceValues(_:)` is marked
`mutating`, so it must be called on a `var` copy of the URL (`var target = url`); the
filesystem write still goes through the underlying path. Calling it on a `let` parameter is a
compile error ("cannot use mutating member on immutable value"), not a silent no-op.

---

## 23. `Picker` with `selection:` resolves to `init(sources:selection:...)` on this toolchain

On Swift 6.4 / Xcode 26.4's SwiftUI, `Picker("Title", selection: binding, content:label:)`
with a trailing `label:` closure resolves to the `init(sources:selection:content:label:)`
overload instead. The compiler then complains that the first positional argument (the title
`String`) does not conform to `RandomAccessCollection`, and the error is a generic-parameter
inference failure that hides the real cause.

Two workarounds that work:
- Use `Menu` with `Button`s instead (what the settings panel does — it is simpler and gives the
  same UX for a short fixed list).
- Drop the trailing-`label:` form and use the older `Picker("Title", selection:binding, content:)`
  where `content:` is a trailing closure.

This is toolchain-specific and may resolve itself on a newer SDK; do not generalise the fix.

---

## 24. CodeEditTextView ignores `NSTextStorage` underline attributes; use `EmphasisManager`

`CodeEditTextView.TextView` does not use standard AppKit/TextKit underline rendering, and
`CodeEditSourceEditor`'s Tree-sitter `Highlighter` invokes `textStorage.setAttributes(...)` on
every token pass, instantly blowing away any attributes attached directly to `textStorage`.

Diagnostic underlines, syntax warnings, and problem highlighting must be added via
`textView.emphasisManager`:
```swift
textView.emphasisManager?.replaceEmphases(
    [Emphasis(range: clampedRange, style: .underline(color: color))],
    for: "CodeEditor.LSP.diagnostics"
)
```
`Emphasis` renders as dedicated `CAShapeLayer`s underneath the text and is preserved across
highlighter updates.

---

## 25. Sidebar chevron buttons in a `List(selection:)` must not mutate selection

In SwiftUI, clicking a `Button` inside a `List` row does not trigger row selection unless the button
action explicitly mutates `selection = item`. When the button did `selection = item`, it caused
both the button action *and* the `List`'s `.onChange(of: selection)` to run `toggleExpansion`.
Because both ran back-to-back, expansion toggled twice and immediately cancelled out whenever an
unselected folder's chevron was clicked.

The disclosure chevron `Button` must only call `fileSystemManager.toggleExpansion(of: item)` and
leave `selection` untouched.

---

## 26. Programmatic sidebar selection must be guarded from triggering `onOpenFile`

When a tab switches, `FileExplorerView` reveals the active document and selects it in the tree.
Without a suppression flag (`isSyncingSelection`), mutating `selection` triggers
`.onChange(of: selection) -> activate() -> onOpenFile()`, firing an asynchronous file open task
that echoes back into the document manager. This created a rapid oscillating feedback loop
fluctuating between tabs and repeatedly reloading the editor view.

Always guard programmatic selection updates with `isSyncingSelection = true` and ensure
`activate` ignores items whose URL already equals `activeDocumentURL`.

---

## 27. AppKit `NSScrollView` floating subviews bleed past SwiftUI views without `.clipped()` and `.zIndex()`

`GutterView` (line numbers) in `CodeEditSourceEditor` is an `NSScrollView` floating subview.
When scrolling, AppKit views can draw over sibling SwiftUI views in a `VStack` because SwiftUI
does not clip view boundaries by default, and later views draw on top of earlier ones.

`editorArea` must be explicitly `.clipped()`, and `TabBarView` must declare `.zIndex(1)` and
`.clipped()` with an opaque base layer so line numbers never bleed or layer into the tab bar.

---

## Quick reference

| Question | Answer |
|---|---|
| Why doesn't CI build? | No runner has SwiftPM 6.4. #1 above. |
| What must I run before pushing? | `swift build && swift test`, plus `swift-format lint --strict`. |
| Can I change `Package.swift`? | Only if you have a Swift 6.3+ toolchain to verify against. See #1. |
| Why is the sidebar slow to show subfolders? | `load` is async and re-renders as children arrive. By design. |
| Why does `Document` not resolve? | `SwiftUI.Document`. Qualify as `CodeEditorCore.Document`. |
| Can I bump CodeEditSourceEditor? | Yes; watch the two files listed in #8. |
| Where do I add a colour? | `Theme.chrome` for chrome, `Theme.semantic` for status. Never a syntax token. |
| Where do I add a spacing value? | `Metrics` in Core. The 4pt grid is enforced by a test. |
| Why did my row tap do nothing? | #12. Drive it from `selection`. |
| Can I derive isDark from colours? | No. #11. |
| Why did the status bar say "1 line selected"? | #17. A caret is not a selection. |
| Does `Scripts/build-app.sh` build? | Only since the fix in #16. Run it from clean to check. |
| Why do all my tabs show the same file? | #18. `SourceEditor` does not diff text on update. |
| What is not covered by `swift test`? | The editor binding, the LSP transport, the LSP-to-view wiring. Open two files and switch tabs. See #18. |
| Does quitting warn me? | Yes, since #18's fix. Force-quit does not, and nothing persists buffers. |
| Where do I write "this does not work"? | Here, and [CURRENT_STATE.md](CURRENT_STATE.md). |
| Why did highlighting fall back to plain text? | #19. The `Language` identifier must match `TreeSitterLanguage.rawValue`. |
| Why are straight quotes not warned? | They are correct in code. #19. |
| Why can't I silently overwrite a file changed on disk? | You can't. #6 throws `DocumentError.changedOnDisk` and the save dialog offers Reload / Save Anyway. |
| How do I make a settings picker? | Don't use `Picker(selection:)`. See #23. Use `Menu` with `Button`s. |
| Where do I add a diagnostic severity colour? | `Theme.semantic` — `.danger`, `.warning`, `.success`. Never a syntax token. |