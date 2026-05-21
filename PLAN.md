# Plan: Rename add-workspace/add-worktree to create-workspace/create-worktree

Simple rename of two recipes and their aliases, plus doc updates.

## Changes

### 1. `justfile`

- Rename recipe `add-workspace` → `create-workspace`
- Rename recipe `add-worktree` → `create-worktree`
- Update aliases: `addws` → `crws`, `addwt` → `crwt`
- Point aliases at the new recipe names

### 2. `AGENTS.md`

- Update the recipe table: `add-workspace` → `create-workspace`, `add-worktree` → `create-worktree`

### 3. `README.md`

- Replace all references to `add-workspace` with `create-workspace`
- Replace all references to `add-worktree` with `create-worktree`
- Update any alias mentions

### 4. `CONTRIBUTING.md`

- Replace all references to `add-workspace` with `create-workspace`
- Replace all references to `add-worktree` with `create-worktree`

## Notes

- Do NOT rename `add-dev` or `add` (those are workspace-level recipes for adding packages/repos)
- The `spawn-agent` skill references `add-workspace` in its SKILL.md — but skills are symlinked from the main workbench `.kiro/skills/`, so do NOT modify them from this worktree (they'd need a separate change)
- Commit and open a PR when done
