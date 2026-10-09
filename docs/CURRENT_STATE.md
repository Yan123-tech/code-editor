# Current state

Last verified against `feature/ui-redesign` on 2026-10-09, Swift 6.4, macOS 27.0.1.

```
swift build    → Build complete
swift test     → 68 tests in 16 suites passed
swift-format lint --strict → 0 warnings
```

Tagged **0.1.0**. The interface has been redesigned since that tag; see
[Redesigned interface](#redesigned-interface).

## Redesigned interface

The window was rebuilt around native macOS chrome. The design tokens live in
`CodeEditorThemes`, the metrics scale in `CodeEditorCore`.

| Area | What it does now |
|---|---|
| **Theme** | `Theme` carries `colorScheme`, a `Chrome` group (accent, sidebar, rows, bars, panels, overlays, borders) and a `Semantic` group (danger, success, warning). Three palettes: Dark, Light, High Contrast. High Contrast sets `usesMaterials = false`. |
| **Typography** | `Typography` maps roles to semantic styles, so chrome scales with the system text size. `.system(size:)` is banned from chrome. The canvas stays a fixed-size SF Mono — code reflowing mid-edit is worse than the accessibility it buys. |
| **Metrics** | One 4pt spacing scale, radii keyed by surface, fixed chrome heights. Enforced by `MetricsTests`. |
| **Toolbar** | Unified: breadcrumb principal, create menu and quick-open/terminal toggles trailing. The sidebar's hand-rolled header is gone. |
| **Sidebar** | Click or arrow to a row to activate: files open, folders expand. The active document is revealed by expanding its ancestors, shown bold with an accent icon. Delete asks first. |
| **Tabs** | 32pt strip, active tab filled with the canvas colour and rounded so it merges with the editor. Dirty dot beside the title; close button always present. |
| **Status bar** | Caret, selection count, UTF-8, line ending, language. The byte count is gone. |
| **Empty state** | One, in the canvas. With a workspace open it points at the sidebar; without one it offers Open Folder as the single prominent action. |
| **Find/replace** | ⌘F opens CodeEdit's own panel through `SourceEditorState.findPanelVisible`. |
| **Quick open** | ⌘P over a bounded filesystem index. Matched characters are emphasised. |
| **Terminal** | Drag-resized 120–600pt, persisted. Semantic status dot, icon buttons, selectable output. |
| **Session** | Workspace root, open tabs and active tab restore on launch. |

## Working

**File explorer.** Recursive tree, lazily loaded — only expanded branches are enumerated.
Create file, create folder, rename, delete, reveal in Finder, copy path. Dotfiles hidden.
New items land beside the active document, or at the workspace root.

**Editing.** `SourceEditor` from CodeEditSourceEditor 0.15, bound two-way to
`Document.content`. Tree-sitter highlighting across roughly 25 languages, line-number
gutter, bracket-pair emphasis, indentation and reformat-at-column, word wrap, undo stack
shared with the document model. Peripherals are configured explicitly: gutter on, minimap
off by default with a toggle, folding ribbon and invisibles toggleable, smart quotes and
invisible spaces flagged as warnings.

**Documents.** Tabs with dirty-state dots. Save, Save All, close with a save prompt.
Untitled documents get a location prompt. Line endings detected on load, preserved on save.

**Terminal.** Runs `$SHELL -i` in a subprocess. Line-buffered scrollback capped at 2000
lines, command history on ↑/↓, stdout and stderr colored separately.

**Themes.** Dark, Light, High Contrast. Selection persists to `UserDefaults`, along with
font size, tab width, word wrap, minimap, folding ribbon and invisibles.

**Commands.** ⌘N, ⌘O, ⇧⌘O, ⌘F, ⌘P, ⌘S, ⌥⌘S, ⌘W, ⌘B, ⌃`, ⇧⌘L. All wired; none are empty closures.

**Tests.** 68 swift-testing cases. `FileSystemManager` and `QuickOpenIndex` are tested
against in-memory providers, so no test touches the real disk.

## Not working

**LSP is implemented but not connected.** `JSONRPCTransport` does real `Content-Length`
framing, correlates responses by id, routes notifications, and fails parked requests rather
than hanging when the server dies. `LSPClient` completes the initialize handshake against
`sourcekit-lsp`. Nothing calls either one. Completion, diagnostics, hover and
go-to-definition are [#1](https://github.com/Yan123-tech/code-editor/issues/1)–[#3](https://github.com/Yan123-tech/code-editor/issues/3).

**The terminal has no PTY.** Pipes, so no job control and no TTY. `vim` renders wrong,
`top` exits immediately, Ctrl-C does not reliably interrupt. [#5](https://github.com/Yan123-tech/code-editor/issues/5).

**No external-change detection.** If a file changes on disk while open, the editor does not
notice and will overwrite it. [#6](https://github.com/Yan123-tech/code-editor/issues/6).

**The quick-open index is a snapshot, not a stream.** It is a filesystem walk refreshed when
the workspace root changes. Files created afterwards are not findable until the next
reindex. Not FSEvents.

**Session restore stores plain paths.** Correct only because the app is not sandboxed.
Under App Sandbox a path can go stale between launches and this would need
security-scoped bookmarks. See [MEMORY.md](MEMORY.md).

**Untitled documents are not restored.** They have no stable identity across launches.

**No multi-cursor.** `TextSelectionManager` models multiple selections and `Document` stores
them, but the text view drives a single caret.

**Single window only.** `Window` replaced `WindowGroup`; a second window would have shared
one `AppState`, one document set and one sidebar. Multi-window needs per-window state first.

**CI does not build.** Format and syntax only. See [MEMORY.md](MEMORY.md).

## Test coverage

| Suite | Cases | Covers |
|---|---|---|
| LineEnding | 1 | detection precedence |
| Language | 1 | extension → language |
| TextSelection | 2 | inverted ranges, NSRange |
| Document | 12 | line splitting, offset math, selection clamping, insert/delete, line endings, line ranges, selected lines |
| Document persistence | 2 | save/reload round-trip, `noURL` |
| DocumentManager | 3 | reuse, neighbour focus, dirty tracking |
| TextSelectionManager | 4 | primary selection, joined text |
| FileSystemManager | 10 | root validation, sort order, create, rename, expansion, cache keys, `reveal`, `clearError` |
| FileSystemItem | 2 | hidden files, icons |
| Metrics | 5 | spacing grid, radii ordering, chrome heights |
| ThemeManager | 4 | appearance per palette, persistence round-trip, unknown name |
| SessionStore | 4 | round-trip, empty, corrupt data, clear |
| FileOutline | 3 | expansion and depth, collapsed branch, depth cap |
| QuickOpenMatcher | 7 | subsequence, ranking, highlight ranges, folding |
| QuickOpenIndex | 4 | relative paths, skipped directories, ranking, empty query |
| TerminalSession | 4 | history, failed connect, clear |

Untested: the view layer in `CodeEditorUI` and `CodeEditorApp` beyond the pure logic
extracted into `CodeEditorCore`, and the LSP transport.

## Next

1. [#1](https://github.com/Yan123-tech/code-editor/issues/1) — connect `LSPClient` via a `TextViewCoordinator`; completion popup
2. [#2](https://github.com/Yan123-tech/code-editor/issues/2) — diagnostics overlay and gutter markers
3. [#3](https://github.com/Yan123-tech/code-editor/issues/3) — hover and go-to-definition
4. [#6](https://github.com/Yan123-tech/code-editor/issues/6) — external change detection
5. [#5](https://github.com/Yan123-tech/code-editor/issues/5) — PTY terminal
6. [#4](https://github.com/Yan123-tech/code-editor/issues/4) — settings panel

`feature/terminal-pty` and [PR #7](https://github.com/Yan123-tech/code-editor/pull/7) exist
as a placeholder branch — plan only, no code.

## Size

| Module | Lines | Files |
|---|---|---|
| CodeEditorCore | 1451 | 8 |
| CodeEditorLSP | 1143 | 3 |
| CodeEditorUI | 1839 | 11 |
| CodeEditorApp | 484 | 2 |
| CodeEditorThemes | 437 | 5 |
| CodeEditorTerminal | 245 | 1 |
| Tests | 969 | 6 |

LSP is the largest module after `CodeEditorUI` and the least used. That is deliberate for
now — it is the interesting part — but if the next three issues do not land, it becomes
dead weight that should be deleted rather than kept aspirational.
