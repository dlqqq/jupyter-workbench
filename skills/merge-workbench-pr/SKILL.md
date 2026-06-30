---
name: merge-workbench-pr
description: Merge an approved workbench PR, then always rebase this workspace onto the latest main. Use when the user approves a workbench PR — "I approve this workbench PR", "merge this PR", "land this PR".
---

# Merge Workbench PR

The user has approved this workspace's workbench PR. Merge it, update the root
workbench's main, then **always** rebase this worktree onto the fresh main.

## When to use

Trigger phrases: "I approve this workbench PR", "merge this PR", "land this".
Run from inside the workspace whose PR was approved.

## How

Two commands, in order. **Always run `just ws rebase` after merging** — a merged
workspace branch is stale, and rebasing recycles the worktree onto the new main
so further work starts from a clean, up-to-date base.

```bash
just workbench merge <pr-number>   # squash-merge the PR, delete its branch, update root main
just ws rebase                     # ALWAYS run this next: reset THIS worktree onto the updated main
```

### `just workbench merge <pr-number>`
- Squash-merges the PR and deletes its **remote** branch (`gh pr merge --squash
  --delete-branch`).
- Fast-forwards the **root worktree's** local `main` to the merged commit. If it
  can't (root checkout dirty or diverged), it warns and continues — the PR is
  still merged; relay the warning so the user can update root main manually.
- Deletes the local branch too, unless it's checked out in a workspace (the next
  step handles that case).

### `just ws rebase` (defaults to the current workspace; pass a name to target another)
- Aborts on uncommitted **tracked** changes (untracked files are preserved).
- Compares the worktree's **tree** against `<remote>/main`. If content exists
  that isn't in main, it aborts and shows the diff — land that first. (A tree
  compare, not a commit compare, because squash-merge rewrites commit identity.)
- Switches the worktree to a fresh dated branch (`YYYYMMDD-<workspace>`,
  timestamp-suffixed on collision) off `<remote>/main`, and deletes the old branch.

If either step aborts, relay the message and help the user resolve it — do not
force past it.
