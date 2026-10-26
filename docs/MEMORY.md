AI completions are provided via `OpenAIClient` and integrated through `CodeSuggestionDelegate`
in `LSPTextViewCoordinator`. When `EditorState.completionMode == .ai`, completion queries bypass
LSP and query the configured OpenAI-compatible endpoint (OpenAI, OpenRouter, Ollama, LM Studio)
with a 200ms debounce to prevent typing churn. Suggestions conform to `CodeSuggestionEntry`
with a `sparkles` icon, `AI (model)` badge, and multi-line documentation preview. Trigger
characters are expanded to include delimiters and operators (`.`, `:`, `/`, `@`, `$`, `_`, `(`,
`{`, `[`, ` `, `=`, `,`, `;`, `>`, `<`, `\n`), and `cleanCompletionText` removes markdown
artifacts and duplicate prefix boundary overlaps.

---

## 33. POSIX Pseudo-Terminal (PTY) and ANSI SGR Parser Architecture

Real terminal interaction requires allocating a POSIX pseudo-terminal (PTY) pair rather than Foundation `Pipe`s:
- `posix_openpt(O_RDWR | O_NOCTTY)` allocates master; `grantpt`, `unlockpt`, and `ptsname` configure and resolve the slave path; and `open(slavePath, O_RDWR | O_NOCTTY)` acquires slave file descriptors.
- In child process configuration, `FileHandle(fileDescriptor: slaveFD, closeOnDealloc: true)` is assigned to `standardInput`, `standardOutput`, and `standardError`.
- **Slave FD Lifetime**: The parent process MUST close its own copy of `slaveFD` immediately after `process.run()`. Otherwise, `masterHandle.readabilityHandler` and `availableData` will keep the stream open indefinitely and never receive EOF when the shell terminates.
- **Window Resizing (`TIOCSWINSZ`)**: Terminal dimensions (`cols`, `rows`) are pushed into the master descriptor via `ioctl(masterFD, TIOCSWINSZ, &ws)`. Darwin kernel delivers `SIGWINCH` to the foreground process in the PTY slave, properly reflowing interactive TUIs (`vim`, `top`, `less`).
- **Foreground Process Interrupts**: Sending `SIGINT` to the shell's PID does not reliably terminate the child program running inside it. Instead, `tcgetpgrp(masterFD)` inspects the active foreground process group, issuing `kill(-pgrp, SIGINT)` along with writing ETX (`0x03`).
- **ANSI Escape Sequence Parsing**: Interactive CLIs (e.g. `brew`, `git clone`, `curl`) rely on carriage returns (`\r`) to overwrite lines in place for progress spinners and percentage meters. `ANSITerminalParser` maintains a cell-based virtual line buffer (`[TerminalCell]`) where `\r` moves `cursorColumn = 0` to allow overwrite, `\x08`/`\x7F` backspaces, CSI `K` erases within the line, and SGR parses styles into `TerminalOutputSpan`s with ANSI standard 16, 256-color table, and 24-bit truecolor support.
- **PTY Resize Debouncing & Drag Smoothness**: Calling `ioctl(masterFD, TIOCSWINSZ, &ws)` on every mouse drag event delivers `SIGWINCH` to the child shell at up to 120Hz, causing the shell to flood stdout with ANSI prompt redraws and thrash layout. `TerminalSession.resize(cols:rows:)` debounces `transport.resize` by 120ms so `SIGWINCH` only fires after dragging settles. Additionally, `terminalDivider` uses `DragGesture(coordinateSpace: .global)` with incremental delta tracking (`currentY - lastY`) encapsulated in `TerminalContainerView` to eliminate clamp dead zones and isolate layout invalidation from the main window.
- **Child Shell CWD Tracking**: Darwin kernel `proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, ...)` queries the child shell's vnode path to dynamically track directory navigation (`cd subdir`) in real time, throttled to 500ms intervals to eliminate syscall churn during streaming output.

---

## 34. Editor Typing / Enter Crash Prevention & NSBezierPath Safety

In AppKit, calling `-[NSBezierPath bounds]` or `-[NSBezierPath controlPointBounds]` on an empty path (`elementCount == 0`) raises an uncaught Objective-C `NSGenericException` (`No current point for control point bounds`), immediately aborting the process (`SIGABRT`).
- **CodeEditTextView `EmphasisManager`**: `updateLayerBackgrounds()` queries `shapePath.bounds` to update `textLayer.frame`. When editing text or pressing Enter, line breaks and offsets change before the language server can re-analyze the buffer. Stale emphasis ranges or newline characters (`\n`) yield zero glyph rects (`rectsFor(range:) == []`), producing an empty `NSBezierPath`.
- **System-Wide Safe Bounds**: `NSBezierPath.installSafeBoundsWorkaround()` swizzles `bounds` and `controlPointBounds` to return `.zero` when empty, eliminating the fatal AppKit exception across the entire app and dependencies.
- **Immediate Diagnostic Invalidation on Edit**: `LSPTextViewCoordinator` implements `willReplaceContentsIn` and `didReplaceContentsIn` to immediately clear diagnostic underlines and jump emphases (`clearDiagnosticUnderlines()`), clearing stale layout layers before AppKit redraws.
- **Non-Empty Glyph Rect Validation**: `renderDiagnosticUnderlines` and `jumpTo(range:)` check `layoutManager.rectsFor(range:).isEmpty` before registering `Emphasis`, preventing empty or newline-only ranges from constructing zero-element underline layers.

---

## Quick reference

| Question | Answer |
|---|---|
| Why doesn't CI build? | No runner has SwiftPM 6.4. #1 above. |
| What must I run before pushing? | `swift build && swift test`, plus `swift-format lint --strict`. |
| Can I change `Package.swift`? | Only if you have a Swift 6.3+ toolchain to verify against. See #1. |
| Why is the sidebar slow to show subfolders? | `load` is async and re-renders as children arrive. By design. |
| Why does `Document` not resolve? | `SwiftUI.Document`. Qualify as `CodeEditorCore.Document`. |
| Can I bump CodeEditSourceEditor? | Yes; watch the two files listed in #8. |
| Where do I add a colour? | `Theme.chrome` for chrome, `Theme.semantic` for status. Never a syntax token. |
| Where do I add a spacing value? | `Metrics` in Core. The 4pt grid is enforced by a test. |
| Why did my row tap do nothing? | #12. Drive it from `selection`. |
| Can I derive isDark from colours? | No. #11. |
| Why did the status bar say "1 line selected"? | #17. A caret is not a selection. |
| Does `Scripts/build-app.sh` build? | Only since the fix in #16. Run it from clean to check. |
| Why do all my tabs show the same file? | #18. `SourceEditor` does not diff text on update. |
| What is not covered by `swift test`? | The editor binding, the LSP transport, the LSP-to-view wiring. Open two files and switch tabs. See #18. |
| Does quitting warn me? | Yes, since #18's fix. Force-quit does not, and nothing persists buffers. |
| Where do I write "this does not work"? | Here, and [CURRENT_STATE.md](CURRENT_STATE.md). |
| Why did highlighting fall back to plain text? | #19. The `Language` identifier must match `TreeSitterLanguage.rawValue`. |
| Why are straight quotes not warned? | They are correct in code. #19. |
| Why can't I silently overwrite a file changed on disk? | You can't. #6 throws `DocumentError.changedOnDisk` and the save dialog offers Reload / Save Anyway. |
| How do I make a settings picker? | Don't use `Picker(selection:)`. See #23. Use `Menu` with `Button`s. |
| Where do I add a diagnostic severity colour? | `Theme.semantic` — `.danger`, `.warning`, `.success`. Never a syntax token. |
| Why did interactive terminal programs like `vim` or `top` fail? | #33. They require a POSIX PTY and window resize ioctls (`TIOCSWINSZ`), not Foundation `Pipe`s. |
| Why did typing or pressing Enter crash in the editor? | #34. `NSBezierPath.bounds` throws on empty path in `EmphasisManager`. Swizzled and cleared on edit. |
