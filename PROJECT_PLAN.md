# Project plan

Superseded by the documents in [`docs/`](docs/). This file is kept only so old links resolve.

| Looking for | Read |
|---|---|
| What this project is for | [docs/IDEA.md](docs/IDEA.md) |
| What works and what does not | [docs/CURRENT_STATE.md](docs/CURRENT_STATE.md) |
| Versions and dependency rationale | [docs/STACK.md](docs/STACK.md) |
| Module boundaries and data flow | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| How work gets done | [docs/PROCESS.md](docs/PROCESS.md) |
| Constraints worth knowing before touching anything | [docs/MEMORY.md](docs/MEMORY.md) |
| Branch and commit conventions | [docs/BRANCHING.md](docs/BRANCHING.md), [docs/COMMITTING.md](docs/COMMITTING.md) |

The original eight-week roadmap planned to hand-roll syntax highlighting in Phase 1.
CodeEditSourceEditor provides it, so that work is gone and the remaining plan is six issues
tracked in GitHub, ordered in [docs/CURRENT_STATE.md](docs/CURRENT_STATE.md).

## Roadmap

| # | Issue | Scope |
|---|---|---|
| 1 | [LSP completion](https://github.com/Yan123-tech/code-editor/issues/1) | Connect `LSPClient` via a `TextViewCoordinator`; fuzzy-filtered popup, Tab/Enter to accept |
| 2 | [Diagnostics](https://github.com/Yan123-tech/code-editor/issues/2) | Consume `textDocument/publishDiagnostics`; underline plus gutter markers |
| 3 | [Hover and go-to-definition](https://github.com/Yan123-tech/code-editor/issues/3) | Tooltips and ⌘-click navigation |
| 6 | [External change detection](https://github.com/Yan123-tech/code-editor/issues/6) | Reload clean files, prompt on dirty ones |
| 5 | [PTY terminal](https://github.com/Yan123-tech/code-editor/issues/5) | Real pseudo-terminal, ANSI parsing, SIGINT forwarding |
| 4 | [Settings panel](https://github.com/Yan123-tech/code-editor/issues/4) | Replace menu-only preference controls |

## Quality gates

- [x] Builds with no warnings
- [x] `swift test` passes (35 tests)
- [x] `swift-format lint --strict` clean
- [ ] CI builds the package — blocked, see [docs/MEMORY.md](docs/MEMORY.md#1-ci-cannot-build-this-package-do-not-try-to-make-it)
- [ ] Completion works for Swift
- [ ] Diagnostics render
- [ ] No leaks in a 30-minute session

## Risks

| Risk | Mitigation |
|---|---|
| Source editor API churn (upstream is pre-1.0) | Pinned `from: 0.15.2`; `Theme.editorTheme` in `EditorTheme+Bridge.swift` isolates the surface we touch. [MEMORY.md #8](docs/MEMORY.md) |
| `sourcekit-lsp` is Xcode-toolchain specific | `LanguageServerRegistry.sourceKitLSPPath` probes known paths and returns `nil` rather than failing to launch |
| URL equality treats `/tmp/x` and `/tmp/x/` as distinct | `FileSystemManager` keys its cache on `standardizedFileURL.path`. [MEMORY.md #3](docs/MEMORY.md) |
| Terminal uses pipes, not a PTY | Documented in `TerminalSession`, tracked as issue #5 |
| LSP is the largest module and unused | If issues 1–3 do not land, delete it rather than keep it aspirational. [CURRENT_STATE.md](docs/CURRENT_STATE.md) |