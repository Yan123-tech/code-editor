# Current state

Last verified on 2026-11-02, Swift 6.4.2, macOS 27.2.0.
Setup native macOS self-hosted CI/CD runner and automated build & test validation in GitHub Actions (Issue #36).
Fixed editor crash on typing/Enter (Issue #34, PR #35); implemented POSIX PTY terminal (PR #7 / Issue #5).

```
swift build    → Build complete (1 pre-existing warning in EditorState.swift)
swift test     → 156 tests in 38 suites (151 unit + 1 sourcekit end-to-end, local-only), 100% passing
swift-format lint --strict → 0 warnings
CI/CD          → format & syntax on macos-latest; build & test on [self-hosted, macOS]
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
