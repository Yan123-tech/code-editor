# Stack

## Toolchain

| Component | Version | Note |
|---|---|---|
| Swift | 6.4 (6.4.0.34.1) | `swift-tools-version: 6.4`, Swift 6 language mode |
| Xcode | 16+ | `ApproachableConcurrency` enabled per target |
| macOS deployment | 14.0 | `@Observable`, `.onChange(of:initial:)`, `.onKeyPress`, `.formStyle(.grouped)` |
| Build system | SwiftPM | no Xcode project, no workspace |

Developed against macOS 27.0.1 arm64. Nothing in the code is version-specific above 14.0;
the 27 SDK is just what is installed.

## Runtime

| Library | Version | Why this one |
|---|---|---|
| [CodeEditSourceEditor](https://github.com/CodeEditApp/CodeEditSourceEditor) | 0.15.2 | The editor. `NSTextView`-backed, tree-sitter highlighting, gutter, bracket emphasis, undo. Built for CodeEdit, so its API is the one that fits a native editor most closely. |
| [CodeEditLanguages](https://github.com/CodeEditApp/CodeEditLanguages.git) | 0.1.20 | Language definitions and tree-sitter queries for ~25 languages. A direct dependency because the UI target needs `CodeLanguage` for editor language resolution. |
| [CodeEditTextView](https://github.com/CodeEditApp/CodeEditTextView.git) | 0.12.1 | Text view primitives. Direct dependency because the UI target needs `CEUndoManager` to share one undo stack between the text view and `Document`. |
| tree-sitter (via SwiftTreeSitter 0.25.0) | transitive | Incremental parsing for highlighting |

Also pulled transitively: `CodeEditSymbols` 0.2.3, `TextFormation` 0.9.0, `TextStory` 0.9.2,
`Rearrange` 2.1.1, `SwiftLintPlugin` 0.65.0.

### On Runestone and the original dependencies

The first manifest pulled in Runestone and SwiftTreeSitter directly, and CodeEditSourceEditor
at `from: "0.1.0"`. Both direct dependencies were unused and produced
`dependency 'runestone' is not used by any target` warnings. Runestone was dropped in favour
of CodeEditTextView: it has the tree-sitter integration and the text formations already
wired, and running two text engines in one app buys nothing.

### Why SourceEditor 0.15 specifically

0.8.1 does not compile against CodeEditTextView 0.12 — it calls
`TextLayoutManager.beginTransaction`, removed in 0.9. 0.15 is the current release and has
the `SourceEditor` + `SourceEditorConfiguration` shape this code targets.

Pinning is `from: "0.15.2"`, so 0.16 will be picked up automatically. That is deliberate:
the upstream package is pre-1.0 and moves. The exposure is contained to three files under
`Sources/CodeEditorUI/Sources/Editor/`: `CodeEditorView.swift` (`SourceEditor`,
`SourceEditorConfiguration` and its nested `Appearance`/`Behavior`/`Peripherals`,
`InvisibleCharactersConfiguration`, `BracketPairEmphasis`), `EditorTheme+Bridge.swift`
(`EditorTheme` and its `Attribute`), and `EditorState.swift` for `IndentOption` alone. A
fourth file naming upstream types means the boundary has leaked. See
[MEMORY.md](MEMORY.md#8-codeeditsourceeditor-is-pre-10-and-moves).

0.15 also ships the pieces this app had no reason to rebuild: a find-and-replace panel
driven by `SourceEditorState.findPanelVisible`, code-folding ribbon, minimap, invisibles
and warning-character rendering. Finding them meant not designing a ⌘F UI at all.

## Tooling

| Tool | Source | Used for |
|---|---|---|
| `swift-format` | ships in the Xcode toolchain | formatting and lint |
| swift-testing | ships in the toolchain | the test suite |
| GitHub Actions | `.github/workflows/ci.yml` | format + syntax checks |

`.swift-format` sets 4-space indentation and a 120-column limit to match the existing
sources. Without it swift-format defaults to 2 spaces and reports 3300+ `Indentation`
warnings, which buries the warnings that matter.

## Decisions

**`@Observable`, not `ObservableObject`.** The original code declared both on the same class,
which stops `@StateObject` from working. Observation, not Combine.

**`ApproachableConcurrency` per target.** Defaults the code assumes — `nonisolated(nonsending)`
parameters, non-isolated deinit — so concurrency is not sprinkled through every signature.

**Swift 6 language mode, strict concurrency.** Errors rather than warnings. Most of the
compile errors in the original scaffold were exactly this.

**`NavigationSplitView` for the layout.** Resizable sidebar, system-standard behaviour, free
on macOS 14+.

**No notifications between `UI` and `App`.** There used to be: the sidebar posted
`.codeEditorOpenFolder` because it could not call `AppState`. It can — views take closures
(`onOpenFile`, `onCreateIn`, `onOpenFolder`) and the panel logic lives in `AppState`, not in
a view. Both notification names are gone. `NSOpenPanel` still does not appear in the view
layer, because `AppState` owns the commands.

## Alternatives rejected

| Considered | Why not |
|---|---|
| Web view (Electron/Tauri) | Not native. Defeats the point. |
| Write our own text view | NSTextView already does selection, undo, IME, accessibility. Reimplementing is a year. |
| Runestone | Duplicate text engine, no tree-sitter integration. |
| SwiftLSPClient | Abandoned upstream. The LSP layer here is small and worth owning. |
| `develop` branch | One line of work. Doubles merge cost for nothing. See [BRANCHING.md](BRANCHING.md). |
| Hand-rolled find/replace | 0.15 ships one. See above. |
| Hand-rolled folding ribbon, minimap, invisibles | 0.15 ships all three as `Peripherals`. |
| More built-in themes | Each one is a palette someone has to maintain and review, for a choice most users make once. Three is enough. |