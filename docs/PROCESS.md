# Process

How work gets done in this repository.

## Before you start

Read [MEMORY.md](MEMORY.md). It holds the constraints that are expensive to rediscover —
the Swift 6.4 toolchain problem in particular will cost you an hour if you do not know it
before you touch `Package.swift`.

Then read [CURRENT_STATE.md](CURRENT_STATE.md) so you know what already works and do not
re-implement it.

## Local gate

This is the gate. CI does not build — see [MEMORY.md](MEMORY.md).

```bash
swift build && swift test
swift-format lint --recursive --strict --configuration .swift-format Sources Tests
```

All three, before every push. 35 tests, about 30 seconds.

`swift-format format --in-place --recursive --configuration .swift-format Sources Tests`
when lint complains about formatting.

## Branching

`main` is the only long-lived branch. Full model in [BRANCHING.md](BRANCHING.md).

```
feature/<description>     new capability
fix/<description>        bug fix
refactor/<description>   behaviour-preserving
chore/<description>      build, CI, dependencies
docs/<description>       documentation
test/<description>       tests
```

One concern per branch. Name it after the issue when there is one:
`feature/lsp-completion` for #1.

```bash
git checkout main && git pull
git checkout -b feature/lsp-completion
# work, committing
git push -u origin feature/lsp-completion
gh pr create --fill
```

## Commits

[Conventional Commits](https://www.conventionalcommits.org/). Full guide in
[COMMITTING.md](COMMITTING.md).

```
<type>(<scope>): <subject>
```

Scopes are modules: `core`, `themes`, `terminal`, `lsp`, `ui`, `app`, `ci`, `docs`.

The body explains **why**, not what. The diff already says what. Write one when the
reasoning is not obvious, or when the obvious approach was wrong and you want the next
reader not to repeat it.

```
fix(core): key the directory cache on standardized paths

URL equality treats /tmp/x and /tmp/x/ as different values, so a rename
left a stale entry under the old key and the sidebar kept showing the old
name. There is a test for this; do not simplify it back to URL.
```

## Pull requests

Fill in the template. Reviewer needs: what changed, why, how it was verified.

- One concern. Split unrelated changes.
- Say what you did *not* verify.
- Link the issue with `Refs #1`, not `Fixes #1` unless the PR actually closes it.

`main` requires a PR and linear history. Force-push is blocked.

## Definition of done

- [ ] `swift build` passes
- [ ] `swift test` passes
- [ ] `swift-format lint --strict` clean
- [ ] New public APIs have doc comments explaining the contract, not restating the name
- [ ] Behaviour change has a test; bug fix has a test that fails without the fix
- [ ] Limitations documented in the PR body or [CURRENT_STATE.md](CURRENT_STATE.md)

## Issues

Every non-trivial piece of work has an issue before it has a branch. The body carries
acceptance criteria as checkboxes — that is the definition of done, written before the work
starts.

Good issue bodies here name modules touched and call out the trap. See
[#1](https://github.com/Yan123-tech/code-editor/issues/1) for the shape.

## Releasing

```bash
# local gate first
swift build && swift test

git tag -a 0.2.0 -m "0.2.0 — <what changed>"
git push origin main --tags
```

The tag message states what is in the release and what is *not* — the 0.1.0 tag lists the
six open issues by number, because someone reading the tag six months later needs to know
what the release does not do.

There is no automation here yet. A release workflow that runs the build on a runner with the
right toolchain is worth adding; it is blocked on the same toolchain problem as CI.

## When something is broken

1. Reproduce it. A test that fails for a reason you cannot state is not a test yet.
2. Write the failing test first if the fix is not obvious.
3. Fix it on a `fix/` branch. Reference the issue.
4. If it needs a workaround, put it in the source next to a comment saying what breaks if it
   can be removed.

Never rewrite history on a pushed branch. `git revert` and explain why in the body.

## When you get stuck

The two things that have consumed the most time in this project:

1. **A dependency that will not build.** Check the dependency's own `Package.swift` for the
   versions it expects, and check whether the failure is a toolchain difference rather than
   your code. See [MEMORY.md](MEMORY.md).
2. **A model that shadows editor state.** If a view keeps its own copy of something
   `Document` also holds, one of them is stale. Find which one is authoritative before
   patching the symptom.

Both cost time because the symptom was far from the cause. Log it in [MEMORY.md](MEMORY.md)
when it happens again.