# CodeEditor MVP — Project Plan

## Current state

The MVP is feature-complete and building green. `swift build` and `swift test` (35 tests)
both pass. `PROJECT_PLAN.md` originally described an eight-week roadmap whose Phase 1 goal
was to hand-roll syntax highlighting; that was replaced by
[CodeEditSourceEditor](https://github.com/CodeEditApp/CodeEditSourceEditor), which provides
the text view, tree-sitter highlighting, gutter and undo handling out of the box.

Shipped:

- File explorer with lazy recursive tree, create / rename / delete
- Editing via `SourceEditor` with tree-sitter highlighting for ~25 languages
- Document tabs, dirty tracking, save with untitled-location prompt
- Line-ending detection and preservation
- Embedded shell terminal with history and 2000-line scrollback
- Three themes with persisted editor preferences
- Menu commands and keyboard shortcuts
- `CodeEditorLSP` transport with real Content-Length framing (not yet wired to the UI)

## Next up

| Issue | Scope |
|---|---|
| LSP completion | Connect `LSPClient` to `SourceEditor` via a `TextViewCoordinator`; fuzzy-filtered popup, Tab/Enter to accept |
| Diagnostics | Consume `textDocument/publishDiagnostics`; underline plus gutter markers |
| Hover and go-to-definition | Tooltips and ⌘-click navigation using `textDocument/hover` and `definition` |
| Settings panel | Persisted preferences UI replacing the current menu-only controls |

## Module boundaries

```
CodeEditorCore          (no dependencies)
CodeEditorThemes        (no dependencies)
CodeEditorTerminal      (no dependencies)
CodeEditorLSP           (no dependencies)
CodeEditorUI            → Core, Themes, Terminal, LSP, CodeEditSourceEditor
CodeEditorApp           → UI, Core, Themes, Terminal, LSP
```

`CodeEditorCore` must stay UI-free so it remains testable without a window server.

## Risks

| Risk | Mitigation |
|---|---|
| Source editor API churn (upstream is pre-1.0) | Pinned to `from: 0.15.2`; the `Theme.editorTheme` bridge in `Sources/CodeEditorUI/Sources/Editor/EditorTheme+Bridge.swift` isolates the surface we depend on |
| `sourcekit-lsp` is Xcode-toolchain specific | `LanguageServerRegistry.sourceKitLSPPath` probes known locations and returns `nil` rather than failing to launch |
| URL equality treats `/tmp/x` and `/tmp/x/` as distinct | `FileSystemManager` keys its cache on `standardizedFileURL.path` |
| Terminal uses pipes, not a PTY | Documented in `TerminalSession`; no job control or terminal echo |

## Quality gates

- [x] Builds with no warnings
- [x] `swift test` passes
- [ ] Completion works for Swift
- [ ] Diagnostics render
- [ ] No leaks in a 30-minute session