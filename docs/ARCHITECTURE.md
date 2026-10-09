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
| `CodeEditorCore` | 958 | `Document`, `DocumentManager`, `TextSelectionManager`, `FileSystemManager`, `Language`, `LineEnding`, `TextSelection` |
| `CodeEditorLSP` | 1143 | `JSONRPCTransport`, `LSPClient`, wire types |
| `CodeEditorUI` | 966 | `CodeEditorView`, `FileExplorerView`, `TerminalView`, `EditorState`, `AppState`, `Theme.editorTheme` |
| `CodeEditorApp` | 370 | `MainWindowView`, `CodeEditorApp`, menu commands |
| `CodeEditorTerminal` | 245 | `TerminalSession` |
| `CodeEditorThemes` | 225 | `Theme`, `EditorColor`, `ThemeManager` |

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

`CodeEditorCore` and `CodeEditorTerminal` are tested; `CodeEditorUI` and `CodeEditorApp` are
not, because they are view code.

The useful pattern is `StubProvider`: an in-memory `FileSystemProvider`, so file-system tests
assert on URLs and names and never touch the real disk or depend on a fixture directory.
Anything that grows a filesystem dependency should use it.

## Where the coupling is

- `SourceEditor` and `EditorTheme.Attribute` — contained in `CodeEditorView.swift` and
  `EditorTheme+Bridge.swift`. Both are upstream, both are pre-1.0. See [STACK.md](STACK.md).
- `Notification.Name.codeEditorOpenFolder` / `codeEditorOpenFiles` — `UI` posts, `App`
  observes. Replace with a closure when a second consumer appears.
- `FileSystemManager.load` returns rows synchronously from a cache while populating it
  asynchronously. The view re-renders as children arrive. Fine for a tree; would need
  thought for a list that must not reflow.

## Adding a module

If a new concern does not fit the six: give it no dependencies, put the model in it, and add
it to `UI`'s dependency list. Do not add it to `App` — anything `App` imports directly cannot
be tested without the app target.

If the concern is UI-only, it belongs in `CodeEditorUI` alongside the views it serves.