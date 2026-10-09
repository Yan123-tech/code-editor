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
| 4 | [Settings panel](https://github.com/Yan123-tech/code-editor/issues/4) | Move persisted preferences out of the Format menu into a discoverable surface |
| 14 | [Interface redesign](https://github.com/Yan123-tech/code-editor/issues/14) | Landed: native macOS chrome and a real design system |

## Quality gates

- [x] Builds with no warnings
- [x] `swift test` passes (68 tests)
- [x] `swift-format lint --strict` clean
- [ ] CI builds the package — blocked, see [docs/MEMORY.md](docs/MEMORY.md#1-ci-cannot-build-this-package-do-not-try-to-make-it)
- [ ] Completion works for Swift
- [ ] Diagnostics render
- [ ] No leaks in a 30-minute session
- [ ] Unsaved work is guarded on quit — **the one remaining path to data loss**, and it is not an issue yet
- [ ] The redesign has been reviewed by someone who can see it

## Risks

| Risk | Mitigation |
|---|---|
| Source editor API churn (upstream is pre-1.0) | Pinned `from: 0.15.2`; three files under `Editor/` name upstream types and no more. [MEMORY.md #8](docs/MEMORY.md) |
| `sourcekit-lsp` is Xcode-toolchain specific | `LanguageServerRegistry.sourceKitLSPPath` probes known paths and returns `nil` rather than failing to launch |
| URL equality treats `/tmp/x` and `/tmp/x/` as distinct | `FileSystemManager` keys its cache on `standardizedFileURL.path`. [MEMORY.md #3](docs/MEMORY.md) |
| Terminal uses pipes, not a PTY | Documented in `TerminalSession`, tracked as issue #5 |
| LSP is the largest module and unused | If issues 1–3 do not land, delete it rather than keep it aspirational. [CURRENT_STATE.md](docs/CURRENT_STATE.md) |
| A build script that passes while doing nothing | `Scripts/build-app.sh` shipped with `--show-bin-path` on its build commands and only ever failed from a clean checkout. Run it from clean. [MEMORY.md #16](docs/MEMORY.md#16-scriptsbuild-appsh-only-fails-from-a-clean-checkout) |
| A document that outlives its code | The redesign broke three claims in `docs/`, one of them describing a notification seam that no longer had a poster. Auditing the `.md` files against the code is part of the work, not after it. [AGENTS.md](AGENTS.md) |