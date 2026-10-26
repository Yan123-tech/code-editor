# Current state

Last verified on 2026-10-26, Swift 6.4.0.34.1, macOS 27.0.1.
Fixed editor crash on typing/Enter (Issue #34, PR #35); implemented POSIX PTY terminal (PR #7 / Issue #5).

```
swift build    → Build complete (1 pre-existing warning in EditorState.swift)
swift test     → 156 tests in 38 suites (151 unit + 1 sourcekit end-to-end, local-only), 100% passing
swift-format lint --strict → 0 warnings
```

Tagged **0.1.0**. The interface has been redesigned since that tag; see
[Redesigned interface](#redesigned-interface) and
[#14](https://github.com/Yan123-tech/code-editor/issues/14).

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
| **Status bar** | Caret, selection count, UTF-8, line ending, language, a live error/warning count from LSP diagnostics (clicking opens a scrollable Problems popover with click-to-jump navigation and line emphasis), and a "Changed on disk" hint while a save conflict is pending. The byte count is gone. |
| **Empty state** | One, in the canvas. With a workspace open it points at the sidebar; without one it offers Open Folder as the single prominent action. |
| **Find/replace** | ⌘F opens CodeEdit's own panel through `SourceEditorState.findPanelVisible`. |
| **Quick open** | ⌘P over a bounded filesystem index. Matched characters are emphasised. |
| **Terminal** | Drag-resized 120–600pt, persisted on drag end. Driven by a genuine POSIX PTY with ANSI SGR color/style support, CR overwrite, debounced TIOCSWINSZ window resize, live child shell CWD tracking (proc_pidinfo), compact repo prompt path, and SIGINT process group forwarding. |
| **Session** | Workspace root, open tabs and active tab restore on launch. |
| **Autocompletion & AI** | User can choose between Language Server (LSP) and AI completions in Settings. Supports any OpenAI-compatible API (OpenAI, OpenRouter, Ollama, LM Studio), with dynamic model fetching/search chooser, Copilot-style suggestions with sparkles icon, and Tab insertion. |

## Working

**File explorer.** Recursive tree, lazily loaded — only expanded branches are enumerated.
Create file, create folder, rename, delete, reveal in Finder, copy path. Dotfiles hidden.
New items land beside the active document, or at the workspace root.

**Editing.** `SourceEditor` from CodeEditSourceEditor 0.15, bound two-way to
`Document.content`. Three defects found in visual review of [#14](https://github.com/Yan123-tech/code-editor/issues/14)
were fixed and all three are confirmed fixed in the running app: every tab showed the first
file opened ([#15](https://github.com/Yan123-tech/code-editor/issues/15) — upstream does not
diff text on update), a selected folder's chevron did nothing
([#16](https://github.com/Yan123-tech/code-editor/issues/16)), and the gutter drew through the
translucent tab strip while rubber-band scrolling
([#17](https://github.com/Yan123-tech/code-editor/issues/17)). Tree-sitter highlighting across 34 languages, line-number
gutter, bracket-pair emphasis, indentation and reformat-at-column, word wrap, undo stack
shared with the document model. Peripherals are configured explicitly: gutter on, minimap
off by default with a toggle, folding ribbon and invisibles toggleable, smart quotes and
invisible spaces flagged as warnings.

**Documents.** Tabs with dirty-state dots. Save, Save All, close with a save prompt.
Untitled documents get a location prompt. Line endings detected on load, preserved on save.
A file that changed on disk since it was opened is detected on save — `save()` throws
`DocumentError.changedOnDisk` and the dialog offers Reload from Disk / Save Anyway / Cancel,
with a "Changed on disk" hint in the status bar. [#6](https://github.com/Yan123-tech/code-editor/issues/6).

**Terminal.** Runs `$SHELL -i` in a real POSIX pseudo-terminal (PTY) master/slave pair
with fallback to pipes. Line-buffered and cell-based scrollback capped at 2000 lines, command
history on ↑/↓. Full ANSI escape sequence support: carriage return (`\r`) in-place overwriting
for spinners and progress bars, backspace (`\x08`/`\x7F`), tab stop alignment, ANSI SGR styling
(bold, dim, italic, underline), 16 standard/bright colors, 256 indexed colors, and 24-bit RGB
truecolor. Propagates window dimensions via debounced `ioctl(TIOCSWINSZ)` (120ms) to reflow full-screen
CLI apps (`top`, `vim`, `nano`) without redraw thrashing during drag, tracks child shell working directory
live via Darwin kernel `proc_pidinfo(PROC_PIDVNODEPATHINFO)`, formats compact prompt paths relative to
the repository root, and forwards `SIGINT` directly to the foreground process group on Ctrl-C.

**Themes.** Dark, Light, High Contrast. Selection persists to `UserDefaults`, along with
font size, tab width, word wrap, minimap, folding ribbon and invisibles.

**Settings panel.** ⌘, opens a sheet (see [#4](https://github.com/Yan123-tech/code-editor/issues/4))
consolidating theme, font size, tab width, view toggles, and autocompletion preferences (LSP vs AI,
endpoint URL, API key, model selection) in one Form.

**Quit guard.** Quitting with modified documents prompts first. Save saves everything and
abandons the quit if any save did not take — a cancelled panel keeps the work; Don't Save
discards; Cancel stays.

**Commands.** ⌘N, ⌘O, ⇧⌘O, ⌘F, ⌘P, ⌘S, ⌥⌘S, ⌘W, ⌘B, ⌃`, ⇧⌘L, ⌘,. All wired; none are empty closures.

**Tests.** 152 swift-testing cases in 37 suites (151 unit + 1 sourcekit end-to-end, local-only).
`FileSystemManager` and `QuickOpenIndex` are tested against in-memory providers, so no
non-LSP test touches the real disk; the LSP transport, parser, and completions are covered by
dedicated suites (see table below).

## Not working

**LSP completion is wired.** `JSONRPCTransport` does real `Content-Length` framing,
correlates responses by id, ACKs server-initiated requests and fails parked requests on crash
or time-out instead of hanging. `LSPClient` completes the `initialize` handshake against
`sourcekit-lsp`, and `LSPTextViewCoordinator` drives open/didChange/close plus the fuzzy
completion popup (Tab/Enter to accept, inline error on server crash or a malformed
response). Diagnostics, hover and go-to-definition are [#2](https://github.com/Yan123-tech/code-editor/issues/2)–[#3](https://github.com/Yan123-tech/code-editor/issues/3): diagnostics
from `textDocument/publishDiagnostics` paint underlines coloured by severity (error/warning/
information/hint) from `Theme.semantic`, a live error/warning count appears in the status bar,
and ⌘-click resolves a definition via `JumpToDefinitionDelegate` with server hover
documentation shown in the link popover. Verified for completion by `LSPClientEndToEndTests`
(local-only; `sourcekit-lsp` is too heavy to run under CI, see [MEMORY.md #1](MEMORY.md)).

Known limits of the LSP wiring:

- `Position` is UTF‑16 code units. The conversion is correct for ASCII but is not yet
  exercised on multi-byte runs — see [MEMORY.md #21](MEMORY.md#21-position-is-utf-16-0-indexed-lsp-spec).
- Document edits are synced as a full `didChange` on a 100ms debounce, not as ranges:
  `SourceEditor` exposes ranges and the coordinator doesn't bridge them yet.
- Each `didOpen` on a `Package.swift` workspace triggers `swift build
  --experimental-prepare-for-indexing` inside sourcekit, which OOMs under `swift test`.
  Use a single-file document. [MEMORY.md #20](MEMORY.md#20-sourcekit-lsp-server-requests-use-string-ids-and-its-completion-must-be-static).
- Diagnostics underlines are a solid coloured underline, not a wavy squiggle — the upstream
  `GutterView` and `TextView` don't expose a squiggle attribute set in 0.15. Gutter markers
  (the red/yellow dots in the scroll ruler) are a follow-up.

**The quick-open index is a snapshot, not a stream.** It is a filesystem walk refreshed when
the workspace root changes. Files created afterwards are not findable until the next
reindex. Not FSEvents.

**Session restore stores plain paths.** Correct only because the app is not sandboxed.
Under App Sandbox a path can go stale between launches and this would need
security-scoped bookmarks. See [MEMORY.md](MEMORY.md).

**Untitled documents are not restored.** They have no stable identity across launches.

**Session restore reopens paths, not edits.** The snapshot stores the workspace root, tab
paths and active path — never buffer content. Quit with unsaved changes and the tab comes
back showing what is on disk. Restoring buffers would mean writing them somewhere, and there
is no untitled-document story yet either. The honest version of this feature is "reopens what
you had open", not "resumes your session".

Quitting itself is guarded: a modified document prompts first
([#18](https://github.com/Yan123-tech/code-editor/issues/18)). Losing the buffer to a
force-quit or a crash is still possible — nothing persists unsaved content anywhere.

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
| Document external change | 5 | mtime guard, baseline resets on save, revert, untitled unguarded |
| Document diagnostics | 4 | setDiagnostics round-trip, range-to-NSRange conversion, Identifiable distinguishability, live typing state |
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
| ANSITerminalParser | 9 | newline splitting, CR overwrite, backspace, tab stops, SGR styles, 256/truecolor, CSI erase in line, fragmented packets, flush |
| PTYTerminalTransport | 2 | real TTY allocation & execution (`test -t 0`), window resize ioctl |
| saveAllModified | 5 | nothing to do, saved, abandoned, mixed outcomes, only-modified visited |
| JSONRPCTransport | 15 | framing, response/error routing (incl. string-id server requests), crash + time-out, `repairMalformedJSON` |
| ServerCapabilities | 2 | object-form capabilities, minimal/bool fallback forms |
| CompletionMatching | 8 | fuzzy filter, sortText ranking, `CompletionList` array/object/extra-field decode |
| DocumentCompletion | 7 | `lspPosition`/`completionPrefix`, UTF-16 code units |
| OpenAI Client & Model Discovery | 5 | URL normalization, OpenAI & Ollama payload decoding, model discovery, prompt construction & response cleanup |
| LSPClientEndToEnd | 1 | `sourcekit-lsp` connect/open/complete; local-only |

## Next

1. **Global Project Search & Replace (Find in Project - ⇧⌘F)** — [#27](https://github.com/Yan123-tech/code-editor/issues/27)
   Search text across all files in the open workspace with regex, case sensitivity, file pattern filters, and match navigation.
2. **Inline Ghost-Text AI Autocompletions** — [#28](https://github.com/Yan123-tech/code-editor/issues/28)
   Upgrade AI suggestions to render inline ghost text following the cursor, accepted with Tab.
3. **Git Gutter & Branch Status Integration** — [#29](https://github.com/Yan123-tech/code-editor/issues/29)
   Visual diff markers in the editor gutter for added/modified/deleted lines and active branch in status bar.
