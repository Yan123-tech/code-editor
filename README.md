# Code Editor

A native macOS code editor built with SwiftUI and Swift 6. It opens a folder, lets you
browse and edit files with tree-sitter syntax highlighting, saves your work, speaks LSP
to language servers, and gives you a genuine embedded POSIX pseudo-terminal in the same window.

<p align="center">
  <em>macOS 14+ &middot; Swift 6.4 &middot; MIT licensed</em>
</p>

## What works today

- **File explorer** — recursive tree with lazy loading, new file/folder, rename, delete,
  reveal in Finder. Dotfiles are hidden.
- **Editing** — a real `NSTextView`-backed editor (via
  [CodeEditSourceEditor](https://github.com/CodeEditApp/CodeEditSourceEditor)) with
  tree-sitter syntax highlighting, line numbers, bracket-pair emphasis, indentation and
  reformat-on-type, word wrap, and a shared undo stack. Protected by swizzled
  `NSBezierPath.safeBounds` preventing AppKit empty path exceptions during rapid editing ([#34](https://github.com/Yan123-tech/code-editor/issues/34), [#35](https://github.com/Yan123-tech/code-editor/pull/35)).
- **Syntax highlighting** for 34 languages (every `TreeSitterLanguage` case `CodeEditLanguages` 0.1.20 exposes) including Swift, Go, JS/TS, JSX/TSX, Python, JSON,
  HTML, CSS, Rust, Java, Ruby, C/C++ and shell.
- **Tabs** — open documents, dirty-state dots, close with a save prompt.
- **Save / Save All**, with a location prompt for untitled documents. Line endings are
  detected on load and preserved on save. A file that changed on disk since it was opened is
  detected on save — the prompt offers Reload, Save Anyway, or Cancel rather than silently
  overwriting it ([#6](https://github.com/Yan123-tech/code-editor/issues/6)).
- **Find and replace** — ⌘F, backed by the source editor's own panel.
- **Quick open** — ⌘P, fuzzy-matching files across the workspace with the matched
  characters highlighted.
- **POSIX Pseudo-Terminal (PTY)** — genuine POSIX pseudo-terminal (`posix_openpt`) running
  your `$SHELL` with ANSI escape sequence parsing (standard 16, 256-color, and 24-bit RGB truecolor),
  in-place carriage-return overwrites (`\r`), full interactive TUI support (`vim`, `top`, `git log`),
  window resize signal propagation (`TIOCSWINSZ`), process-group interrupts, and live CWD tracking ([#5](https://github.com/Yan123-tech/code-editor/issues/5), [#7](https://github.com/Yan123-tech/code-editor/pull/7)). Toggle with `^``; drag the divider to resize.
- **Language Server Protocol (LSP)** — `sourcekit-lsp` starts on Swift documents, and `gopls` starts
  on Go documents ([#17](https://github.com/Yan123-tech/code-editor/issues/17)). Autocompletions are
  fuzzy-filtered, accept with Tab or Enter, and handle crashes or malformed server envelopes gracefully
  without wedging the editor ([#1](https://github.com/Yan123-tech/code-editor/issues/1), [#38](https://github.com/Yan123-tech/code-editor/issues/38)). Go documents format automatically on save with `gofmt`.
- **LSP Diagnostics & Problems Navigator** — live error and warning markers in the gutter, squiggly
  underlines beneath issue ranges, status bar summary counts, a scrollable Problems inspector popover
  with click-to-jump line navigation, and jump shortcuts (`⌘'` / `⇧⌘'`) ([#2](https://github.com/Yan123-tech/code-editor/issues/2), [#10](https://github.com/Yan123-tech/code-editor/pull/10)).
- **AI Autocompletions** — configurable OpenAI-compatible completion backend supporting OpenAI, Ollama,
  LM Studio, and OpenRouter with debounced query dispatch, multi-line documentation previews, and markdown
  cleanup ([#21](https://github.com/Yan123-tech/code-editor/issues/21), [#22](https://github.com/Yan123-tech/code-editor/pull/22)).
- **Themes** — Dark, Light and High Contrast, persisted across launches along with font
  size, tab width, word wrap, minimap, folding ribbon and invisibles.
- **Settings Panel** — native macOS Settings window (`⌘,`) with dedicated tabs for General,
  Editor, Terminal, Themes, and AI ([#4](https://github.com/Yan123-tech/code-editor/issues/4), [#8](https://github.com/Yan123-tech/code-editor/pull/8)).
- **Session restore** — reopens your workspace and tabs on launch. It restores *what you
  had open*, not your edits: unsaved buffers are not persisted, and untitled documents
  have no path to replay.
- **Quit guard** — quitting with unsaved changes asks first. Choosing Save abandons the
  quit if anything failed to save, so a cancelled dialog never costs you the work.
- **Menu commands** — ⌘N, ⌘O, ⇧⌘O, ⌘F, ⌘P, ⌘S, ⌥⌘S, ⌘W, ⌘B, ^`, ⇧⌘L, ⌘,.

### Interface notes

The window uses native macOS chrome: a unified toolbar with a breadcrumb, a navigator that
opens files and expands folders on click or arrow key, a tab strip whose active tab merges
into the editor, and a single empty state that adapts to whether a workspace is open.

Design tokens are not sprinkled through the views. Colours live in `Theme.chrome` and
`Theme.semantic` — chrome never borrows a syntax token. Spacing, radii and chrome heights
live in `Metrics` in `CodeEditorCore`, on a 4pt grid. Chrome type is semantic, so it scales
with your system text size; the code font stays fixed-size on purpose.

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

### Build the .app bundle

`swift run` gives you the binary, not an application — no Dock tile, no menu bar, no
double-clickable file. To get `build/Code Editor.app`, run:

```bash
Scripts/build-app.sh
```

The script builds in release, lays out `Contents/{MacOS,Resources}`, copies every SwiftPM
resource bundle into `Contents/Resources` (CodeEditLanguages grammars and CodeEditSymbols
assets are resolved through `Bundle.module`, which looks them up under `Bundle.main.resourceURL`),
renders `AppIcon.icns` from `Scripts/make-icon.swift`, and ad-hoc signs the bundle.

| Flag | Effect |
|---|---|
| `--debug` | Build the debug product instead of release |
| `--install` | Also copy the bundle to `/Applications` |
| `--open` | Launch it when the build finishes |

Ad-hoc signing is enough locally and for handing the bundle to another Mac. To distribute it
further, swap the `codesign` identity in the script for a Developer ID and notarize the zipped
bundle.

Format and lint with `swift-format`, which ships inside the Xcode toolchain:

```bash
swift-format format --in-place --recursive --configuration .swift-format Sources Tests
swift-format lint --recursive --strict --configuration .swift-format Sources Tests
```

## Continuous integration

CI runs on every Pull Request and push to `main` across three automated jobs:

| Job | Environment | What it does |
|---|---|---|
| Format | `macos-latest` (Hosted) | `swift-format lint --strict`, then reformat and fail if `git diff` is non-empty |
| Syntax | `macos-latest` (Hosted) | `swiftc -parse` on every source file |
| Build & Test | `[self-hosted, macOS]` (Apple Silicon) | Full `swift build`, `swift test` (156 tests across 38 suites), and `./Scripts/build-app.sh --debug` bundle layout and codesign |

The package requires Swift 6.4 toolchain capabilities (`swift-tools-version: 6.4`) and native macOS AppKit / SwiftUI frameworks. Compilation and test execution run on a dedicated native Apple Silicon self-hosted runner (`yan-macbook-runner`) managed via `launchd`, guaranteeing that every PR compiles cleanly and satisfies all unit and end-to-end test suites.

## Project layout

| Module | Responsibility |
|---|---|
| `CodeEditorCore` | `Document`, `DocumentManager`, `TextSelectionManager`, `FileSystemManager`, `FileOutline`, `QuickOpenMatcher`, `QuickOpenIndex`, `RecentProjectsStore`, `SessionStore`, `Metrics`. No UI — Foundation only. |
| `CodeEditorThemes` | `Theme`, `Chrome`, `Semantic`, `Typography`, `EditorColor`, `ThemeManager` with persisted selection. |
| `CodeEditorTerminal` | `TerminalSession`, `PTYTerminalTransport`, `ANSITerminalParser`: POSIX pseudo-terminal subprocess, ANSI SGR color parsing, window resizing, scrollback. |
| `CodeEditorLSP` | `JSONRPCTransport` (Content-Length framing, response correlation, server-request ACK, crash/time-out handling), `LSPClient` (initialize handshake, document sync, diagnostics, completions), `LanguageServerRegistry`, `GoFormatter`, and `OpenAIClient`. Wired to the editor via `LSPTextViewCoordinator`. |
| `CodeEditorUI` | SwiftUI views: editor, sidebar, tabs, status bar, empty state, quick open, terminal, settings, plus `AppState`. |
| `CodeEditorApp` | The `@main` App, menu commands, window layout, toolbar. |

Dependencies flow one way: `Core` ← `UI` ← `App`. `Themes`, `Terminal` and `LSP` are
leaves that `UI` composes.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `⌘N` | New file |
| `⌘O` | Open folder |
| `⇧⌘O` | Open files |
| `⌘F` | Find |
| `⌘P` | Quick open |
| `⌘S` / `⌥⌘S` | Save / Save all |
| `⌘W` | Close tab |
| `⌘B` | Toggle sidebar |
| `` ^` `` | Toggle terminal |
| `⌘'` / `⇧⌘'` | Next / Previous diagnostic problem |
| `⇧⌘L` | Toggle dark/light theme |
| `⌘,` | Settings |

## Documentation

| Document | What it covers |
|---|---|
| [docs/IDEA.md](docs/IDEA.md) | What this is for, what it deliberately is not, design principles |
| [docs/CURRENT_STATE.md](docs/CURRENT_STATE.md) | What works, what does not, test coverage, next steps |
| [docs/STACK.md](docs/STACK.md) | Toolchain and dependency versions, with the reasoning for each choice |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Module boundaries, data flow, concurrency, where coupling lives |
| [docs/PROCESS.md](docs/PROCESS.md) | Local gate, branching, PRs, definition of done, releasing |
| [docs/MEMORY.md](docs/MEMORY.md) | Constraints that are expensive to rediscover |
| [docs/BRANCHING.md](docs/BRANCHING.md) | Branch naming and the PR flow |
| [docs/COMMITTING.md](docs/COMMITTING.md) | Conventional Commits types and scopes |
| [AGENTS.md](AGENTS.md) | Instructions for coding agents working here |

`docs/MEMORY.md` is the one to read first. It records constraints such as why `FileSystemManager`
keys on paths rather than `URL`s, how POSIX PTY process group signaling operates, and why
`NSBezierPath.safeBounds` swizzling prevents empty-path exceptions during typing.

If a change makes any of these documents wrong, fixing the document is part of the change.
See [AGENTS.md](AGENTS.md).

## Roadmap

1. [Completion popup](https://github.com/Yan123-tech/code-editor/issues/1) — completed
2. [Diagnostics overlay & Problems popover](https://github.com/Yan123-tech/code-editor/issues/2) — completed ([#10](https://github.com/Yan123-tech/code-editor/pull/10))
3. [External change detection](https://github.com/Yan123-tech/code-editor/issues/6) — completed
4. [PTY terminal](https://github.com/Yan123-tech/code-editor/issues/5) — completed ([#7](https://github.com/Yan123-tech/code-editor/pull/7))
5. [Settings panel](https://github.com/Yan123-tech/code-editor/issues/4) — completed ([#8](https://github.com/Yan123-tech/code-editor/pull/8))
6. [Go language adaptation & gofmt on save](https://github.com/Yan123-tech/code-editor/issues/17) — completed ([#18](https://github.com/Yan123-tech/code-editor/pull/18))
7. [AI completion provider integration](https://github.com/Yan123-tech/code-editor/issues/21) — completed ([#22](https://github.com/Yan123-tech/code-editor/pull/22))
8. [App icon liquid glass HIG redesign](https://github.com/Yan123-tech/code-editor/issues/30) — in progress ([#31](https://github.com/Yan123-tech/code-editor/pull/31))
9. [Find in Project / global search & replace (⇧⌘F)](https://github.com/Yan123-tech/code-editor/issues/27) — planned
10. [Git gutter diff markers & branch indicator](https://github.com/Yan123-tech/code-editor/issues/29) — planned
11. [Hover and go-to-definition](https://github.com/Yan123-tech/code-editor/issues/3) — planned

## Contributing

`main` is the only long-lived branch and must always build green. Branch off it as
`feature/…`, `fix/…`, `chore/…`, `docs/…` or `test/…`, commit in
[Conventional Commits](https://www.conventionalcommits.org/) form, and open a PR.

- Branching model and PR flow: [docs/BRANCHING.md](docs/BRANCHING.md)
- Commit types and scopes: [docs/COMMITTING.md](docs/COMMITTING.md)
- Full workflow: [docs/PROCESS.md](docs/PROCESS.md)

Before pushing, verify formatting with `swift-format lint --strict Sources Tests` and ensure all tests pass (`swift test`). CI validates formatting, syntax, module compilation, unit tests, and `.app` packaging automatically on every PR.

## License

[MIT](LICENSE)
