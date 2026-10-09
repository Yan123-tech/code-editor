# Branching

`main` is the only long-lived branch. It must build and have green tests at every
commit, because CI runs on it and it is what gets tagged.

Work on short-lived branches that branch from the latest `main`:

```
feature/<short-description>     new capability
fix/<short-description>        bug fix
chore/<short-description>      build, CI, dependencies
docs/<short-description>       documentation only
test/<short-description>       tests only
refactor/<short-description>   behaviour-preserving change
```

One concern per branch. If a review comment needs a substantial new change, add it as a
second commit rather than amending — the reviewer can see the change react to feedback.

Name branches after the issue where one exists: `feature/lsp-completion` for issue #12.

## Flow

1. `git checkout main && git pull`
2. `git checkout -b feature/lsp-completion`
3. Work, committing in Conventional Commits form.
4. `swift build && swift test` locally before pushing.
5. `git push -u origin feature/lsp-completion`
6. Open a PR against `main`. Fill in the template.
7. After review, squash-merge or merge with a merge commit. Squash for a branch with
   noisy intermediate commits; merge when reviewers want the sequence preserved.
8. Delete the branch. `main` moves on.

## Why no `develop` branch

The project has one active line of work. A `develop` branch means every change has to be
merged twice and every bug fix has to be applied in two places. If two features need to be
in flight at once, branch both from `main` and merge them in whichever order they finish —
Git handles that fine, and it keeps `main` always deployable.

If that stops being true — releases on a cadence, or several people on unrelated features —
revisit then and introduce a `release/*` line instead.