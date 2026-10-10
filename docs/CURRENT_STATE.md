# Current state

Last verified against `feature/ui-redesign` on 2026-10-09, Swift 6.4, macOS 27.0.1.

```
swift build    → Build complete
swift test     → 68 tests in 16 suites passed
swift-format lint --strict → 0 warnings
```

Tagged **0.1.0**. The interface has been redesigned since that tag; see
[Redesigned interface](#redesigned-interface) and
[#14](https://github.com/Yan123-tech/code-editor/issues/14).

**Start here:** the highest-priority next step is not one of the six issues — it is guarding
unsaved work on quit, which is the only remaining path to data loss. See
[Next](#next).

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
`Document.content`. Three defects found in visual review of [#14](https://github.com/Yan123-tech/code-editor/issues/14)
were fixed: every tab showed the first file opened
([#15](https://github.com/Yan123-tech/code-editor/issues/15) — upstream does not diff text on
update), a selected folder's chevron did nothing
([#16](https://github.com/Yan123-tech/code-editor/issues/16)), and the gutter drew through the
translucent tab strip while rubber-band scrolling
([#17](https://github.com/Yan123-tech/code-editor/issues/17) — fix applied, not yet
confirmed). Tree-sitter highlighting across roughly 25 languages, line-number
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

**Session restore reopens paths, not edits, and nothing guards unsaved work on quit.** The
snapshot stores the workspace root, tab paths and active path — never buffer content. Quit
with unsaved changes and the tab comes back showing what is on disk, with the edits gone and
no prompt on the way out. There is no `applicationShouldTerminate` handler, so the app does
not even ask. Restoring buffers would mean writing them somewhere, and there is no
untitled-document story yet either. The honest version of this feature is "reopens what you
had open", not "resumes your session".

This is the only remaining path to data loss in the app, which is why it tops
[Next](#next).

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

The redesign ([#14](https://github.com/Yan123-tech/code-editor/issues/14),
[PR #13](https://github.com/Yan123-tech/code-editor/pull/13)) changed what is cheap and what
is not, so the old ordering no longer holds. Below is what I would pick next and why —
this is a recommendation, not a commitment. The issues are unchanged.

### 1. Guard unsaved work before anything else

**No issue yet — worth opening.** Session restore persists paths, never buffer content, and
there is no prompt when the app terminates. Quit with unsaved edits and the tab reopens
showing what is on disk, with the work gone and nothing said. This is the only gap that can
lose data, and the redesign made it more visible by making restore feel like it resumes.

Small: a termination handler that asks when modified documents are open, plus a decision
about whether to persist buffers or not. Data loss outranks features.

### 2. #1 — LSP completion

The client already works; nothing calls it. `SourceEditor` takes a `completionDelegate`, so
this is wiring rather than design — the least code for the most visible gain, and the
project's stated purpose ([IDEA.md](IDEA.md)). The suggestion UI already exists upstream too;
the same way ⌘F did not need building.

### 3. #6 — external change detection

A file changed on disk while open is silently overwritten. Also data loss, but narrower: it
needs someone else editing the same file. A prompt on save when the modification date moved
is enough to start; FSEvents is not required for correctness here.

### 4. #2 then #3 — diagnostics, hover, go-to-definition

Follow #1 naturally: they share the transport and lifecycle that #1 proves. Doing them
together means the `TextViewCoordinator` wiring is designed once.

### 5. #4 — settings panel

Smallest of the six. Minimap, folding ribbon, invisibles, wrap, tab width and font size are
already toggles in the Format menu and already persisted; the panel is moving existing
state into a discoverable surface, not new behaviour.

### 6. #5 — PTY terminal

Largest and least user-visible until done. `vim` and `top` are broken today, which makes it
feel urgent, but it is C interop behind a protocol and nothing else depends on it.

### Deliberately not next

- **More themes.** Each one is a palette someone maintains and reviews, for a choice most
  users make once. Three is enough.
- **Multi-window.** Needs per-window `AppState` first. The `Window` scene is the honest
  single-window shape, not a compromise.
- **Finder file associations.** Needs `CFBundleDocumentTypes` in `App-Info.plist` and
  `.handlesExternalEvents`. Small, but it is packaging rather than capability, and it
  should ride along with something that needs double-clicking files to work — which is
  completion via ⌘P, not the other way round.

### Housekeeping before the next branch

- [#16](https://github.com/Yan123-tech/code-editor/issues/16) and
  [#17](https://github.com/Yan123-tech/code-editor/issues/17) are fixed but were not driven in
  the running app — synthetic accessibility events do not reach SwiftUI rows, and the gutter
  overlap only appears mid-gesture. Both need a second look.
- `Scripts/build-app.sh` needs running from a clean checkout before it is believed again.
  See [MEMORY.md #16](MEMORY.md#16-scriptsbuild-appsh-only-fails-from-a-clean-checkout).

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
