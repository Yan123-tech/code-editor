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

CI runs two jobs, both of which work on any hosted macOS runner:

| Job | What it does |
|---|---|
| Format | `swift-format lint --strict`, then reformat and fail if `git diff` is non-empty |
| Syntax | `swiftc -parse` on every source file |

**Build and test do not run in CI.** The package declares `swift-tools-version: 6.4`
because `CodeEditSourceEditor` 0.15 needs SwiftPM 6.4 to generate its resource bundles, and
no hosted runner carries it — they top out at 6.3.3. Lowering the manifest to 6.3 clears
SwiftPM but then fails inside a dependency: `CodeEditSymbols` 0.2.3 declares no resources in
its own manifest, so SwiftPM 6.3 does not emit `Bundle.module`.

So `swift build` and `swift test` are a local and release-time gate for now. That means CI
does not catch type errors or test failures; if you add a self-hosted runner with Xcode 26.4,
add a `build` job and drop the caveat.

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

`docs/MEMORY.md` is the one to read first. It records why CI cannot build this package, why
`FileSystemManager` keys on paths rather than `URL`s, and which source editor API is safe to
depend on — each of which cost real time to work out.

If a change makes any of these documents wrong, fixing the document is part of the change.
See [AGENTS.md](AGENTS.md).

## Roadmap

`CodeEditorLSP` has a working transport — real `Content-Length` framing, request/response
correlating by id, notification routing — and a `sourcekit-lsp` descriptor that resolves
Xcode's bundled binary. It is not connected to the editor yet.

1. [Completion popup](https://github.com/Yan123-tech/code-editor/issues/1)
2. [Diagnostics overlay](https://github.com/Yan123-tech/code-editor/issues/2)
3. [Hover and go-to-definition](https://github.com/Yan123-tech/code-editor/issues/3)
4. [External change detection](https://github.com/Yan123-tech/code-editor/issues/6)
5. [PTY terminal](https://github.com/Yan123-tech/code-editor/issues/5)
6. [Settings panel](https://github.com/Yan123-tech/code-editor/issues/4)

## Contributing

`main` is the only long-lived branch and must always build green. Branch off it as
`feature/…`, `fix/…`, `chore/…`, `docs/…` or `test/…`, commit in
[Conventional Commits](https://www.conventionalcommits.org/) form, and open a PR.

- Branching model and PR flow: [docs/BRANCHING.md](docs/BRANCHING.md)
- Commit types and scopes: [docs/COMMITTING.md](docs/COMMITTING.md)
- Full workflow: [docs/PROCESS.md](docs/PROCESS.md)

Before pushing, run `swift build && swift test` locally — CI checks formatting and syntax
only, for the toolchain reason described above.

## License

[MIT](LICENSE)