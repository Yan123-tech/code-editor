# Idea

## What this is

A native macOS code editor: open a folder, browse it, edit files with real syntax
highlighting, save them, and run a shell in the same window. Nothing else.

## Why it exists

Two reasons, and it matters that they are separate.

**A working editor.** There is no good reason this project should not produce a usable
editor on a Mac. The interesting constraint is that everything should be native: SwiftUI
and AppKit, no web view, no Electron, no runtime to install. What you get is a binary that
starts in under a second, uses system text rendering, and behaves like a Mac app rather
than a website in a frame.

**A testbed for LSP.** Most editor features above syntax highlighting are language-server
features, not editor features. Completion, diagnostics, hover and go-to-definition are the
same LSP requests in every editor; the hard part is the transport and the lifecycle, not the
UI. `CodeEditorLSP` implements that layer from scratch — framing, request correlation,
notification routing, process lifecycle — so it can be read, tested and reasoned about
without an IDE around it.

## What it is not

- **Not a replacement for Xcode or Zed.** It has no build system integration, no refactoring,
  no multi-cursor editing, no extension system. Those are large projects.
- **Not a general-purpose IDE.** The focus is text editing plus language intelligence.
- **Not trying to out-feature anything.** Each feature should earn its place by being either
  cheap and genuinely useful, or a demonstration that the underlying machinery works.

## Shape of the thing

```
┌────────────────────────────────────────────────────┐
│  ⌃sidebar   breadcrumb          create ⌕ terminal    │
├────────────┬───────────────────────────────────────┤
│            │  tabs (active merges into the canvas) │
│  explorer  ├───────────────────────────────────────┤
│  (tree)    │                                       │
│            │  editor + tree-sitter highlighting    │
│            │  gutter · bracket emphasis · undo     │
│            ├───────────────────────────────────────┤
│            │  status bar: Ln/Col · UTF-8 · language│
├────────────┴───── drag handle ─────────────────────┤
│  terminal (toggleable, resizable)                  │
└────────────────────────────────────────────────────┘
```

Three panels, one window, no chrome that is not doing work. The sidebar is resizable, the
terminal hides entirely and is drag-resized, and the editor takes whatever is left.

Two invariants hold the interface together. **Chrome never borrows a colour from syntax** —
window furniture reads `Theme.chrome`, status reads `Theme.semantic`. And **the chrome has
one type ramp, one spacing grid and one set of heights**, all in code, none of them inline
literals.

## Principles

**Native or nothing.** If a capability requires a web view or a subprocess bridge to do, it
does not belong here.

**The document model is the truth.** `CodeEditorCore.Document` owns content, line endings,
selection and dirty state. The text view binds to it; it does not shadow it. Anything that
duplicates editor state is a bug waiting to happen.

**Write the boring layer properly.** LSP framing and file-system caching have no UI to hide
behind. They are where correctness actually gets tested.

**Say what does not work.** A documented limitation is worth more than a silent gap. The
terminal uses pipes rather than a PTY, and [issue #5](https://github.com/Yan123-tech/code-editor/issues/5)
exists because of it.

## Where it is going

Near term, connect the LSP client that already works: completion, diagnostics, hover,
go-to-definition. That is issues [#1](https://github.com/Yan123-tech/code-editor/issues/1)–[#3](https://github.com/Yan123-tech/code-editor/issues/3).

Longer term it is unclear whether this grows into a full editor or stays a focused tool. That
is a decision to make when there is more evidence about what is missing, not now.

## Related documents

- [CURRENT_STATE.md](CURRENT_STATE.md) — what works, what does not, what is next
- [STACK.md](STACK.md) — versions and dependency rationale
- [ARCHITECTURE.md](ARCHITECTURE.md) — module boundaries and data flow
- [PROCESS.md](PROCESS.md) — how work gets done here
- [MEMORY.md](MEMORY.md) — constraints that are easy to forget and expensive to rediscover