# Current state

Last verified against `main` on 2026-10-09, Swift 6.4, macOS 27.0.1.

```
swift build    → Build complete
swift test     → 35 tests in 10 suites passed
swift-format lint --strict → 0 warnings
```

Tagged **0.1.0**.

## Working

**File explorer.** Recursive tree, lazily loaded — only expanded branches are enumerated.
Create file, create folder, rename, delete, reveal in Finder, copy path. Dotfiles hidden.
Double-click a file to open it; single-click a folder to set the create-target.

**Editing.** `SourceEditor` from CodeEditSourceEditor 0.15, bound two-way to
`Document.content`. Tree-sitter highlighting across roughly 25 languages, line-number
gutter, bracket-pair emphasis, indentation and reformat-at-column, word wrap, undo stack
shared with the document model.

**Documents.** Tabs with dirty-state dots. Save, Save All, close with a save prompt.
Untitled documents get a location prompt. Line endings detected on load, preserved on save.
UTF-8 byte and line counts in the status bar.

**Terminal.** Runs `$SHELL -i` in a subprocess. Line-buffered scrollback capped at 2000
lines, command history on ↑/↓, stdout and stderr colored separately.

**Themes.** Dark, Light, High Contrast. Selection persists to `UserDefaults`, along with
font size, tab width and word wrap.

**Commands.** ⌘N, ⌘O, ⇧⌘O, ⌘S, ⌥⌘S, ⌘W, ⌘B, ⌃`, ⇧⌘L. All wired; none are empty closures.

**Tests.** 35 swift-testing cases. `FileSystemManager` is tested against an in-memory
provider, so no test touches the real disk.

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

**No multi-cursor.** `TextSelectionManager` models multiple selections and `Document` stores
them, but the text view drives a single caret.

**No find/replace panel.** `SourceEditorState` has the fields for it
(`findText`, `replaceText`, `findPanelVisible`); nothing surfaces them.

**CI does not build.** Format and syntax only. See [MEMORY.md](MEMORY.md).

## Test coverage

| Suite | Cases | Covers |
|---|---|---|
| LineEnding | 1 | detection precedence |
| Language | 1 | extension → language |
| TextSelection | 2 | inverted ranges, NSRange |
| Document | 9 | line splitting, offset math, selection clamping, insert/delete, line endings, line ranges |
| Document persistence | 2 | save/reload round-trip, `noURL` |
| DocumentManager | 3 | reuse, neighbour focus, dirty tracking |
| TextSelectionManager | 4 | primary selection, joined text |
| FileSystemManager | 6 | root validation, sort order, create, rename, expansion, cache keys |
| FileSystemItem | 2 | hidden files, icons |
| TerminalSession | 4 | history, failed connect, clear |

Untested: `CodeEditorUI` and `CodeEditorApp` entirely (they are view code), the LSP
transport, and `ThemeManager` persistence.

## Next

In order, by issue:

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
| CodeEditorCore | 958 | 3 |
| CodeEditorLSP | 1143 | 3 |
| CodeEditorUI | 966 | 6 |
| CodeEditorApp | 370 | 2 |
| CodeEditorTerminal | 245 | 1 |
| CodeEditorThemes | 225 | 1 |
| Tests | 498 | 2 |

LSP is the largest module and the least used. That is deliberate for now — it is the
interesting part — but if the next three issues do not land, it becomes dead weight that
should be deleted rather than kept aspirational.