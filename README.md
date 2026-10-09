# Code Editor

A native macOS code editor built with SwiftUI and Swift 6. It opens a folder, lets you
browse and edit files with tree-sitter syntax highlighting, saves your work, and gives you
an embedded shell in the same window.

<p align="center">
  <em>macOS 14+ &middot; Swift 6.4 &middot; MIT licensed</em>
</p>

## What works today

- **File explorer** — recursive tree with lazy loading, new file/folder, rename, delete,
  reveal in Finder. Dotfiles are hidden.
- **Editing** — a real `NSTextView`-backed editor (via
  [CodeEditSourceEditor](https://github.com/CodeEditApp/CodeEditSourceEditor)) with
  tree-sitter syntax highlighting, line numbers, bracket-pair emphasis, indentation and
  reformat-on-type, word wrap, and a shared undo stack.
- **Syntax highlighting** for ~25 languages including Swift, JS/TS, JSX/TSX, Python, JSON,
  HTML, CSS, Go, Rust, Java, Ruby, C/C++ and shell.
- **Tabs** — open documents, dirty-state dots, close with a save prompt.
- **Save / Save All**, with a location prompt for untitled documents. Line endings are
  detected on load and preserved on save.
- **Embedded terminal** — runs your `$SHELL`, with scrollback capped at 2000 lines,
  command history on ↑/↓, and separate stdout/stderr coloring.
- **Themes** — Dark, Light and High Contrast, persisted across launches along with font
  size, tab width and word wrap.
- **Menu commands** — ⌘N, ⌘O, ⇧⌘O, ⌘S, ⌥⌘S, ⌘W, ⌘B, ⌃`, ⇧⌘L for theme.

## Requirements

- macOS 14 or later
- Xcode 16 / Swift 6.4 toolchain

## Getting started

```bash
git clone https://github.com/Yan123-tech/code-editor.git
cd code-editor
swift build
swift run CodeEditorApp
```

Run the tests with:

```bash
swift test
```

## Project layout

| Module | Responsibility |
|---|---|
| `CodeEditorCore` | `Document`, `DocumentManager`, `TextSelectionManager`, `FileSystemManager`. No UI. |
| `CodeEditorThemes` | `Theme`, `EditorColor`, `ThemeManager` with persisted selection. |
| `CodeEditorTerminal` | `TerminalSession`: shell subprocess, line-buffered scrollback, history. |
| `CodeEditorLSP` | `JSONRPCTransport` (Content-Length framing) and `LSPClient`. Not yet wired into the UI. |
| `CodeEditorUI` | SwiftUI views: editor, sidebar, terminal, plus `AppState`. |
| `CodeEditorApp` | The `@main` App, menu commands, window layout. |

Dependencies flow one way: `Core` ← `UI` ← `App`. `Themes`, `Terminal` and `LSP` are
leaves that `UI` composes.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `⌘N` | New file |
| `⌘O` | Open folder |
| `⇧⌘O` | Open files |
| `⌘S` / `⌥⌘S` | Save / Save all |
| `⌘W` | Close tab |
| `⌘B` | Toggle sidebar |
| `` ⌃` `` | Toggle terminal |
| `⇧⌘L` | Toggle dark/light theme |

## Roadmap

`CodeEditorLSP` has a working transport — real `Content-Length` framing, request/response
correlating by id, notification routing — and a `sourcekit-lsp` descriptor that resolves
Xcode's bundled binary. It is not connected to the editor yet. Planned, in order:

1. Completion popup with fuzzy filtering and keyboard navigation
2. Diagnostics overlay with gutter markers
3. Hover tooltips
4. Go-to-definition
5. Settings panel

See [`PROJECT_PLAN.md`](PROJECT_PLAN.md) for the full roadmap.

## Contributing

`main` is the only long-lived branch and must always build green. Branch off it as
`feature/…`, `fix/…`, `chore/…`, `docs/…` or `test/…`, commit in
[Conventional Commits](https://www.conventionalcommits.org/) form, and open a PR.

- Branching model and PR flow: [docs/BRANCHING.md](docs/BRANCHING.md)
- Commit types and scopes: [docs/COMMITTING.md](docs/COMMITTING.md)

CI runs `swift build` and `swift test` on macOS for every push and PR.

## License

[MIT](LICENSE)