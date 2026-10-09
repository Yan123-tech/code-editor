# Commit messages

[Conventional Commits](https://www.conventionalcommits.org/): `<type>(<scope>): <subject>`.

```
<type>(<scope>): <subject>
                      ← blank line
<body>
                      ← blank line
<footer>
```

## Types

| Type | Use for |
|---|---|
| `feat` | a new capability the user can observe |
| `fix` | a bug fix |
| `refactor` | behaviour-preserving internal change |
| `perf` | a measurable speedup |
| `build` | dependencies, build settings, package manifest |
| `test` | tests only |
| `docs` | documentation only |
| `chore` | housekeeping with no source impact |

## Scopes

Use the module or area: `core`, `themes`, `terminal`, `lsp`, `ui`, `app`, `ci`, `docs`.

## Subject

Imperative mood, no trailing period, under 72 characters.

```
fix(core): clamp selections to content bounds        ← good
Fixed the selection bug in the core.                  ← bad
fix(core): fix a bug where selections were wrong     ← bad, says "fix" twice
```

## Body

Explain *why*, not *what* — the diff already shows what changed. Worth writing when the
reasoning is not obvious from the code, or when the obvious approach was wrong and you
want the next reader not to repeat it.

```
The old insertText(_:at: utf8Offset:) guarded on
'location.length > 0', which rejects every insert made at a cursor
position. Selection length is 0 exactly when the caret is collapsed.
```

## Examples from this repository

```
build: adopt CodeEditSourceEditor 0.15 for the editing surface

refactor(core): rewrite document, file system and selection models

fix(terminal): correct appendOutput, drop ObservableObject, add history

feat(lsp): real Content-Length framing and request/response routing

feat(ui): real editing, recursive sidebar and shared AppState

test: cover document offsets, persistence, file system and terminal

docs: document what actually ships, not the original roadmap
```

## Reverting

`git revert <sha>`, and put the revert's reason in the body. Never rewrite a commit that
has been pushed to a shared branch.