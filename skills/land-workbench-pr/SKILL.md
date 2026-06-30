---
name: land-workbench-pr
description: Approve and merge the current workspace's workbench PR, then reset the worktree to a fresh branch off the updated main. Use when the user says "I approve this workbench PR", "land this PR", "merge and reset", or similar.
---

# Land Workbench PR

The user has approved the workbench PR for this workspace. Merge it and recycle
the worktree onto a fresh branch off the latest `main`.

## When to use

Trigger phrases: "I approve this workbench PR", "land this PR", "merge and reset".
Only valid from **inside a workspace** that has an open workbench PR.

## How

Run from the workspace root:

```bash
just land
```

`just land` does the whole sequence and is safe to hand the output back to the user:

1. **Dirty check** — if there are uncommitted *tracked* changes, it aborts and
   lists them. Commit/stash/discard, then re-run. (Untracked files are preserved
   across the reset and only listed as an FYI.)
2. **Squash-merges** the open PR for the current branch (`gh pr merge --squash
   --delete-branch`), resolving the remote and repo from the worktree's git config.
3. **Fetches** the updated `main`.
4. **Resets this worktree** onto a fresh dated branch (`YYYYMMDD-<workspace>`,
   suffixed with a timestamp if that branch already exists) off `<remote>/main`.
5. **Deletes** the old merged branch locally.

If anything aborts (dirty tree, no open PR), relay the message to the user and
help them resolve it — do not force past it.
