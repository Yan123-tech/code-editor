# Architecture

## Modules

Six targets, dependencies flowing one way.

```
CodeEditorCore      ┐
CodeEditorThemes    │
CodeEditorTerminal  ├─→ CodeEditorUI ─→ CodeEditorApp
CodeEditorLSP       ┘
```

`Core`, `Themes`, `Terminal` and `LSP` have no dependencies on each other. `UI` composes
them. `App` is the only target that owns a window.

| Module | Lines | Owns |
|---|---|---|
| `CodeEditorCore` | 1478 | `Document`, `DocumentManager`, `TextSelectionManager`, `FileSystemManager`, `FileOutline`, `QuickOpenMatcher`, `QuickOpenIndex`, `SessionStore`, `Metrics`, `Language`, `LineEnding`, `TextSelection` |
| `CodeEditorLSP` | 1143 | `JSONRPCTransport`, `LSPClient`, wire types |
| `CodeEditorUI` | 1904 | `CodeEditorView`, `FileExplorerView`, `TabBarView`, `StatusBarView`, `EmptyStateView`, `QuickOpenView`, `TerminalView`, `EditorState`, `AppState`, `Theme.editorTheme` |
| `CodeEditorApp` | 559 | `MainWindowView`, `CodeEditorApp`, `AppDelegate` (quit guard), menu commands |
| `CodeEditorTerminal` | 245 | `TerminalSession` |
| `CodeEditorThemes` | 437 | `Theme`, `Chrome`, `Semantic`, `Typography`, `EditorColor`, `ThemeManager` |

## Where the design system lives

Two modules, split by what they may import:

- **`CodeEditorThemes`** — colours and type. `Theme` holds the canvas and syntax tokens, a
  `Chrome` group for window furniture, a `Semantic` group for status colours, and the
  `colorScheme` the window forces. `Typography` maps roles to semantic styles.
- **`CodeEditorCore`** — `Metrics`, the spacing scale, radii and fixed chrome heights. It is
  pure layout arithmetic, so it stays in the Foundation-only module and its invariants are
  testable without a window server.

The rule that matters: **chrome never borrows a syntax token.** The accent used to be
`Theme.keyword`, which meant the tab underline, folder icons, the terminal prompt and
terminal errors all changed meaning whenever the syntax palette did.

Views must not introduce a literal font size or a padding off the 4pt grid. `MetricsTests`
fails if the grid is broken; nothing enforces the font rule automatically, so `.system(size:)`
outside `CodeEditorThemes` is a review item.

## The rule that matters

**`CodeEditorCore` must not import SwiftUI or AppKit.** It is the layer worth testing
without a window server, and it is where the subtle logic lives — offset arithmetic, line
ending conversion, path-keyed caching. If a `NSRange` becomes inconvenient, that is a
signal the model wants a better API, not an `import AppKit`.

`CodeEditorCore` imports `Foundation` only. Everything else may import freely.

## Data flow

The document is the source of truth. The text view does not own content.

```
user types
    │
    ▼
SourceEditor ──text binding──→ Document.setContent(_:)
    │                              │
    │                              ├─→ lines[] recomputed
    │                              ├─→ isModified = true
    │                              └─→ delegate.documentDidModify
    │
    └──cursorPositions──→ Document.setSelection(location:)
                              │
                              ▼
                        EditorState.syncSelection
                              │
                              ▼
                        status bar reads caretLine/caretColumn
```

The reverse — `Document` notifying the view — is deliberately absent. `SourceEditor` takes a
`Binding<String>`, so the text view reads `Document.content` on every render. A push model
would need a re-entrancy guard against the text view writing while SwiftUI is mid-update.

**Consequence:** `Document` mutations that originate outside the text view (nothing today)
would fight the binding. If you add one, route it through the view, not around it.

## Three more flows worth knowing

**Find panel.** One flag, two owners. `EditorState.isFindVisible` is ours;
`SourceEditorState.findPanelVisible` is the editor's. `CodeEditorView` syncs them both ways,
and the panel is the authority: when the user dismisses the panel, the coordinator writes
`findPanelVisible = false`, which we mirror back onto `EditorState`. ⌘F only ever sets our
flag. Nothing in the app draws a find UI.

**Session restore.** `AppState` is the `DocumentManagerDelegate`, so opening and closing a
document persists a `SessionSnapshot` — workspace root, open tab paths, active path — to
`UserDefaults` via `SessionStore`. On launch it replays it. Untitled documents are skipped
because they have no path to replay. A vanished root clears the snapshot rather than leaving
a window that restores nothing.

**Quick open.** `QuickOpenIndex` walks the workspace off the main actor in batches and
publishes each batch only if its generation is still current, so a superseded walk is
dropped rather than interleaved. `QuickOpenMatcher` scores candidates per keystroke against
what is already indexed; the palette renders and nothing else. It is a snapshot — see
[CURRENT_STATE.md](CURRENT_STATE.md).

## Caching and identity

`FileSystemManager` keys its directory cache on `url.standardizedFileURL.path`, not `URL`.

This is not a micro-optimisation. `URL` equality treats `/tmp/x` and `/tmp/x/` as different
values — same file, different `absoluteString`. Keying on `URL` produced two cache entries
for one directory, so after a rename the sidebar kept showing the old name from the entry
keyed on the pre-rename URL. There is a test for this
(`FileSystemManager.cacheKeysIgnoreTrailingSlash`); do not "simplify" it back to `URL`.

```swift
childrenByPath[pathKey(for: url)]   // stable across trailing slashes and `.` segments
loadingPaths: Set<String>            // in-flight guard, same key space
expandedPaths: Set<String>          // expansion state, same key space
```

All three use the same key type deliberately.

## Concurrency

Every observable model is `@MainActor @Observable`. Views observe them; none of them own
threads.

Two things cross the boundary:

- **`JSONRPCTransport` is an `actor`.** It owns a `Process` and drains pipes on a background
  queue, so reads cannot race. Responses are `Data` that the client decodes.
- **`Task.detached` for file I/O.** `Document.load` and `Document.save` hop off the main
  actor and back. Reading a 500 KB file should not stutter the UI.

`deinit` is the trap. A `@MainActor` class cannot touch its isolated state from `deinit`,
which is why `TerminalSession.disconnect()` exists and callers use it explicitly.

## LSP layering

Three layers, each independently testable:

```
LSPClient                  protocol lifecycle, MainActor, observable
    │                      connect / openDocument / completion / hover / definition
    ▼
JSONRPCTransport           actor: framing, id correlation, notification routing
    │                      does not know what a Position is
    ▼
Process + pipes            xcrun sourcekit-lsp
```

The transport is the piece worth reading. It accumulates bytes into a buffer and emits only
complete `Content-Length`-framed messages, so a response split across two pipe reads still
parses. It resumes parked continuations by id, and resumes *all* of them with an error when
the server dies — otherwise a crashed language server would hang the editor forever.

`Types/LSPTypes.swift` holds the wire types and nothing else. It was split out of a
1169-line `LSPClient.swift` that mixed the two.

`CompletionList` decodes from either a bare array or the wrapper object, because servers
disagree on which they send. `Hover` only decodes `MarkupContent`, not the three-way
`MarkedString | MarkupContent | MarkedString[]` union — sourcekit-lsp does not send the
others, and the union adds decoding branches nothing exercises.

## Tests

`CodeEditorCore`, `CodeEditorThemes` and `CodeEditorTerminal` are tested; `CodeEditorUI` and
`CodeEditorApp` are not, because they are view code.

The rule when view code grows real logic: **move the logic to `CodeEditorCore` and test it
there.** The sidebar's tree flattening became `FileOutline`; quick open became
`QuickOpenMatcher` plus `QuickOpenIndex`. Neither had to change behaviour to be tested.

`UserDefaults`-backed state takes its domain from the caller rather than reaching for
`.standard`, which is why `SessionStore` and `ThemeManager` are testable.

The useful pattern is `StubProvider`: an in-memory `FileSystemProvider`, so file-system tests
assert on URLs and names and never touch the real disk or depend on a fixture directory.
Anything that grows a filesystem dependency should use it.

## Where the coupling is

- `SourceEditor` and `EditorTheme.Attribute` — contained in `CodeEditorView.swift` and
  `EditorTheme+Bridge.swift`. Both are upstream, both are pre-1.0. See [STACK.md](STACK.md).
- `DocumentTextCoordinator` — a `TextViewCoordinator` that captures the live
  `TextViewController` so `CodeEditorView` can reload its text. Exists because
  `updateNSViewController` does not diff the text behind the binding. A fourth upstream-type
  file is expected and accounted for; see [MEMORY.md #18](MEMORY.md).
- `SourceEditorState.findPanelVisible` — `EditorState.isFindVisible` is our flag,
  `CodeEditorView` syncs it both ways, and the upstream coordinator opens the panel when
  state disagrees with it. The panel stays the authority on its own visibility.
- `TreeSitterClient.Constants.longParse` — a notification name from the upstream module.
  The editor surfaces it as a parse indicator; nothing else depends on it.
- `Notification.Name.codeEditorOpenFolder` / `codeEditorOpenFiles` — **removed.** The seam
  existed because the sidebar used to own an "Open Folder" button and could not call
  `AppState` directly. It can now: the sidebar takes an `onCreateIn` closure and the canvas
  empty state takes `onOpenFolder`, and the panel itself lives in `AppState`. Both
  notifications posted and observed inside `CodeEditorApp`, which is a round trip to
  nowhere. Call closures.
- `FileSystemManager.load` returns rows synchronously from a cache while populating it
  asynchronously. The view re-renders as children arrive. Fine for a tree; would need
  thought for a list that must not reflow.

## Adding a module

If a new concern does not fit the six: give it no dependencies, put the model in it, and add
it to `UI`'s dependency list. Do not add it to `App` — anything `App` imports directly cannot
be tested without the app target.

If the concern is UI-only, it belongs in `CodeEditorUI` alongside the views it serves.