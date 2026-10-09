# AGENTS.md

Instructions for coding agents working in this repository.

## Read this first

Before changing any code:

1. **[docs/MEMORY.md](docs/MEMORY.md)** — constraints that are expensive to rediscover.
   Entry #1 alone will cost you an hour if you touch `Package.swift` without it.
2. **[docs/CURRENT_STATE.md](docs/CURRENT_STATE.md)** — what works, what does not, what is
   next. Do not re-implement something that already works.
3. **[docs/IDEA.md](docs/IDEA.md)** — what this project is for, and what it deliberately is not.

---

## Keeping the documentation true is part of the work

**The `.md` files in `docs/` describe the current state of the code. If your change makes any
of them wrong, fixing that file is not optional cleanup — it is part of the change.**

This matters more here than in most projects, because `docs/MEMORY.md` is the only record of
several constraints that cost real time to discover. A stale entry does not just misinform a
reader; it sends the next person — or the next agent — into the same dead end, and they have
no way to tell the file is stale.

### When to update which file

| Your change | Update |
|---|---|
| Anything in `Sources/` or `Tests/` that changes what works | **CURRENT_STATE.md** — features, tests table, sizes |
| Worked around a dependency, a toolchain limit, an SDK quirk | **MEMORY.md** — new numbered entry, or amend the relevant one |
| Found a trap you fell into | **MEMORY.md** — what happened, what it cost, what to do |
| Added, removed or upgraded a dependency | **STACK.md** — versions table and the rationale below it |
| Added or removed a module, or changed a data flow | **ARCHITECTURE.md** |
| Changed how work is expected to happen | **PROCESS.md**, **BRANCHING.md**, **COMMITTING.md** |
| Changed what the project is for | **IDEA.md** |
| Changed the public surface, CI, or setup | **README.md** |

### The rule

If you had to read something to understand your change, it belonged in a `.md` file and
probably does not exist yet. Write it.

If you found something that contradicts a `.md` file, fix the file in the same commit. A
stale document is a defect, not a matter of taste — and it is worse than a missing one,
because a missing file announces ignorance while a wrong file is trusted.

### When the current state is knowingly wrong

Do not paper over it. Write it down as a limitation with an issue number, the way
`TerminalSession`'s pipes-not-a-PTY is handled:

```
## Not working

**The terminal has no PTY.** Pipes, so no job control and no TTY.
[#5](https://github.com/Yan123-tech/code-editor/issues/5)
```

An honest gap is useful. A hidden gap is a trap for whoever inherits this.

---

## Local gate — CI does not build

**Run all three before every push. CI checks formatting and syntax only.**

```bash
swift build && swift test
swift-format lint --recursive --strict --configuration .swift-format Sources Tests
```

Reason: no hosted runner has SwiftPM 6.4, which `CodeEditSourceEditor` 0.15 needs to
generate its resource bundles. Full details and the failed attempts in
[docs/MEMORY.md](docs/MEMORY.md#1-ci-cannot-build-this-package-do-not-try-to-make-it).

Never imply in a commit message or PR that CI verified the build. It did not.

---

## Conventions

- **Conventional Commits**, scopes are modules: `core`, `themes`, `terminal`, `lsp`, `ui`,
  `app`, `ci`, `docs`. See [docs/COMMITTING.md](docs/COMMITTING.md).
- **One concern per branch.** `main` is protected: PR required, linear history, no
  force-push. See [docs/BRANCHING.md](docs/BRANCHING.md).
- **4-space indent, 120 columns.** Enforced by `.swift-format`.
- **`CodeEditorCore` imports `Foundation` only** — no SwiftUI, no AppKit. That is what makes
  it testable without a window server, and what makes offset arithmetic testable at all.
- **Chrome never borrows a syntax token.** Colours come from `Theme.chrome` or
  `Theme.semantic`. The accent was once `Theme.keyword`, which made the tab underline, folder
  icons, the terminal prompt and terminal errors change meaning with the syntax palette.
- **No magic numbers in chrome.** Spacing, radii and fixed heights come from `Metrics`
  (`CodeEditorCore`); the 4pt grid is enforced by a test. Chrome type comes from
  `Typography` — semantic styles only, so it scales with the user's text size. Code keeps a
  fixed-size SF Mono. See [MEMORY.md](docs/MEMORY.md#11) for why these rules exist.

## Traps that will bite

- `Document` is ambiguous inside modules that import SwiftUI. Write `CodeEditorCore.Document`.
- Never key a dictionary or set by `URL` where the path is what matters. See
  [MEMORY.md #3](docs/MEMORY.md).
- Do not add `ObservableObject` to anything. It is `@Observable` throughout.
- Do not give a `@MainActor` class a `deinit` that touches its state.
- `SourceEditor` takes a `Binding<String>`; there is no push path from `Document` to the
  view. See [MEMORY.md #4](docs/MEMORY.md).
- A `.onTapGesture` on a row inside a `List(selection:)` never fires. Drive row behaviour
  from the selection change. See [MEMORY.md #12](docs/MEMORY.md#12-a-tap-gesture-inside-a-selection-list-is-swallowed).
- Do not put a `.frame` on a `NavigationSplitView` column; `.navigationSplitViewColumnWidth`
  already sizes it. See [MEMORY.md #13](docs/MEMORY.md).

## Before you call it done

- [ ] `swift build` passes
- [ ] `swift test` passes
- [ ] `swift-format lint --strict` clean
- [ ] Behaviour change has a test; bug fix has a test that fails without the fix
- [ ] New public APIs have doc comments that state the contract
- [ ] View code with real logic moved into `CodeEditorCore` and tested there
- [ ] The `.md` files above are still true

That last item is not a formality. It is the difference between this repository and one
where the next hour is wasted.