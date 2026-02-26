---
name: git-conventions
description: Git branching, topic management, and bug fix workflow conventions for Anoma.
---

# Git Conventions

## Terminology

- **topic** — any branch that fixes a problem or adds a feature.
- **base** — the branch to base new work off of (typically the latest release tag).
- **next** — superset of features for the next release; topics merge here for integration testing.
- **main** / **master** — the same branch, prepares for a release.
  Some repos use `master`, some use `main`.
- **maint** — maintenance branch for patch releases.

## Naming

Name topics `name/description` (e.g., `mariari/fix-ordering-unchecked-mnesia`).

## Core Principles

1. **One concern per topic.** If you spot an unrelated bug in the
   same file, make a separate topic for it.

2. **Base topics on base**, not on `main` or `next`.  Basing on
   `main` drags in unrelated merges, creates spurious conflict bases,
   and prevents other topics from cleanly reusing your work.

3. **Base bug fixes on the commit that introduced the bug.**  This
   lets the fix merge cleanly into any `maint` branch.  Use
   `git blame` to find the introducing commit.

4. **Merge other people's topics into yours** if you need their
   work — don't rebase onto `main`.

5. **No evil merges.**  A merge commit should contain only conflict
   resolution.  Every line in the combined diff must trace to exactly
   one parent.  Verify with `git show --cc <merge>`.

   If a merge requires changes beyond what rerere can handle, make
   those in a **separate commit** prefixed `evil!` that references
   which merge caused it.  This keeps the extra work visible and
   reproducible when the integration branch is rerolled.  Evil
   commits get squashed when the work is finalized.

## Building on Existing Work

Topics chain on each other as work progresses.  If your fix or
feature depends on another topic, merge that topic into yours.

- **Find existing topics** before starting work:
  ```bash
  git branch -a | grep <keyword>
  gh pr list --search <keyword>
  ```

- **Chain topics:** build each on top of the previous when changes
  are related.  Long chains are normal since releases are infrequent.

- **Merge dependencies, don't rebase.**  Since topics are well-based,
  merging only picks up the relevant changes.

## Bug Fix Workflow

1. **Find the introducing commit** with `git blame`.
2. **Branch from it:** `git checkout -b name/fix-description <commit>`
3. **Fix, verify** (formatter, linter, tests), **commit.**
4. **Merge into the integration branch** (e.g., `next`, `base`, or
   a parent topic), resolve conflicts.  If changes beyond conflict
   resolution are needed, put them in a separate `evil!` commit.

## Commit Messages

- First line: imperative summary of what changed.
- Body: explain what was wrong and the fix rationale.
