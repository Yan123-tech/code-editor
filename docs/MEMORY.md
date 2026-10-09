# Memory

Constraints and facts that are expensive to rediscover. Each entry says what happened, what
it cost, and what to do about it.

**This file is the reason the other documents exist.** If a change makes something here
wrong, fix the file in the same PR.

---

## 1. CI cannot build this package. Do not try to make it.

**The constraint.** `Package.swift` declares `swift-tools-version: 6.4`. No hosted GitHub
runner carries SwiftPM 6.4.

**What was tried, all failing:**

| Attempt | Runner | Toolchain | Result |
|---|---|---|---|
| `xcode-select -s /Applications/Xcode_16.app` | macos-latest | — | `invalid developer directory` — path absent from the image |
| default toolchain | macos-latest | 6.3.3 | manifest 6.4 rejected |
| `setup-xcode` `latest-stable` | macos-15 | 6.2.4 | older still |
| Xcode 26 explicit | macos-26 | 6.3.3 | still short of 6.4 |

**Why lowering the manifest does not work.** Setting `swift-tools-version: 6.3` gets past
SwiftPM, then fails inside a dependency:

```
CodeEditSymbols/CodeEditSymbols.swift:14:42: error: type 'Bundle' has no member 'module'
```

`CodeEditSymbols` 0.2.3 has `Sources/CodeEditSymbols/Symbols.xcassets` but its own
`Package.swift` declares **no** `resources:`. SwiftPM 6.4 infers the bundle and synthesises
`Bundle.module`; 6.3 does not. Every version of that package, 0.1.1 through 0.2.3, has the
same omission — there is no version to pin to.

**Why downgrading the editor does not work.** `CodeEditSourceEditor` gained the
`CodeEditSymbols` dependency at 0.13.0, so 0.12.x avoids it. But 0.12.x requires a
CodeEditTextView 0.10 API that no longer exists:

```
MinimapLineFragmentView.swift:46: error: method does not override any method from its superclass
MinimapLineRenderer.swift:32: error: incorrect argument label in call
```

The 0.11.x line fails the same way on a different API change. There is no working
combination on an old toolchain.

**Current state.** CI runs two jobs that work everywhere:

- **Format** — `swift-format lint --strict`, then `format --in-place` and fail if
  `git diff` is non-empty. `swift-format` ships in the Xcode toolchain, so it is present
  regardless of Swift version.
- **Syntax** — `swiftc -parse` on every file. Parsing does not resolve the dependency graph,
  so it needs no SwiftPM.

Branch protection has **no** required status check, because there is nothing that can pass.

**The cost of this is real.** CI does not catch type errors or failing tests. Every
contributor must run the local gate. Say so in PRs rather than implying CI covered it.

**What unblocks it.** A runner with Xcode 26.4. Then add a `build` job and re-add
`build-and-test` as a required check in one commit.

---

## 2. `swift-format` needs the config or it reports nothing useful

`.swift-format` sets 4-space indentation, 120 columns.

Without it, `swift-format` defaults to 2 spaces and reports **3301** `Indentation` warnings
across 18 files. The real warnings — `OrderedImports`, `DoNotUseSemicolons`, `TrailingComma`
— are invisible in that noise.

With the config: 75 warnings, all real, all fixable. Zero after applying.

Applying the formatter also surfaced two genuine defects the original code had, which
suggests it is worth running before review, not only in CI:

- Semicolon-separated statements in the sidebar context menu
- Unordered import blocks

---

## 3. `URL` equality is not path equality

`URL(fileURLWithPath: "/tmp/x") != URL(fileURLWithPath: "/tmp/x/")`. Same file, different
`absoluteString`.

`FileSystemManager` keys its cache on `url.standardizedFileURL.path` for this reason. Keyed
on `URL`, a rename left the stale entry under the pre-rename key and the sidebar kept
displaying the old filename — the tree appeared to ignore the rename entirely.

Test: `FileSystemManager.cacheKeysIgnoreTrailingSlash`. **Do not simplify it back to `URL`.**

Related trap: `deletingLastPathComponent()` returns a URL *with* a trailing slash. So
`root.appendingPathComponent("x").deletingLastPathComponent() != root` even though the paths
are identical.

---

## 4. The document is the source of truth; the text view binds to it

`SourceEditor` takes a `Binding<String>`. `CodeEditorView` supplies
`Binding(get: { document.content }, set: { document.setContent($0) })`.

There is no push path from `Document` to the text view. That is deliberate: a push model
would need a re-entrancy guard against the text view writing while SwiftUI is mid-update.

**Consequence:** a `Document` mutation originating outside the text view will fight the
binding. Route it through the view. If you add one, you will need to think about this.

`Document` mutations all funnel through one private `apply(_:)`, which recomputes `lines`,
sets `isModified` and notifies the delegate in one place. Keep it that way — the original had
four methods that each did a subset, and the line cache drifted from the content.

---

## 5. `@Observable` and `ObservableObject` are mutually exclusive here

The original `TerminalSession` declared both. That stops `@StateObject` from working — the
type is no longer `ObservableObject`, so `@StateObject` will not accept it, and the error
points at the property wrapper rather than the conformance.

Everything is `@Observable` now. Views hold models via `@State` or `@Bindable`.

Same class of trap: a `@MainActor` class cannot touch its isolated state from `deinit`.
`TerminalSession` has no `deinit`; callers use `disconnect()`.

---

## 6. `Document` is ambiguous with `SwiftUI.Document`

Inside `CodeEditorUI` and `CodeEditorApp`, which import SwiftUI, the bare name `Document`
resolves ambiguously. Use `CodeEditorCore.Document`.

This appears in type positions: parameters, stored properties, `ForEach` element types.
It does *not* shadow value-level uses like `document.content`.

---

## 7. The terminal is pipes, not a PTY

`TerminalSession` spawns `$SHELL -i` with three `Pipe()`s. No job control, no TTY.

Consequences, all expected: `vim` renders wrong, `top` exits immediately, Ctrl-C writes
`0x03` into a pipe the shell does not read as a signal.

This is documented in the type's doc comment and tracked as
[#5](https://github.com/Yan123-tech/code-editor/issues/5). Not an oversight — a PTY layer is C
interop and belongs behind a testable protocol.

---

## 8. CodeEditSourceEditor is pre-1.0 and moves

Pinned `from: "0.15.2"`, so 0.16 lands automatically. That is intentional.

Exposure is contained to two files:

- `Sources/CodeEditorUI/Sources/Editor/EditorTheme+Bridge.swift` — the only place that
  constructs `EditorTheme.Attribute`
- `Sources/CodeEditorUI/Sources/Editor/CodeEditorView.swift` — `SourceEditor` and
  `SourceEditorConfiguration`

Keep it that way. If a third file starts naming upstream types, the boundary has leaked.

Known break: 0.8.1 → 0.15 changed the API completely (`CodeEditorSourceEditor` with
`cursorPositions:` became `SourceEditor` with `state: SourceEditorState`), and 0.8.1 no
longer compiles against CodeEditTextView 0.12 at all.

---

## 9. Xcode-build-system leftovers in `.build`

`.build/out/` holds artifacts from an Xcode-driven build, and `swift build` will use
`-D Xcode`. This is stale state from before the package was restructured. If a build behaves
inexplicably, `rm -rf .build` before debugging anything else.

`.build/` is gitignored. `/build` is also ignored because Xcode writes there.

---

## 10. History was rebuilt once

The first published history contained commits that captured stale file contents, caused by
a `git reset --hard` mid-task. The published `main` was reconstructed from scratch and
verified green, so what is on the remote is correct — but part of that work was redone.

The lesson is procedural and it is in [BRANCHING.md](BRANCHING.md): work on feature branches
and merge, rather than rewriting history in place. It is much harder to lose a day's work
that way.

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
| Where do I write "this does not work"? | Here, and [CURRENT_STATE.md](CURRENT_STATE.md). |