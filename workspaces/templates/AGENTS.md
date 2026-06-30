# Workspace Agent Guide

You are a worker agent assigned to a task inside a workspace. Your workspace is a **git worktree** of the workbench repo on branch `YYYYMMDD-<name>`. Your venv is already activated. Stay in your workspace. If you need another package, use `just dev add`. Do NOT spawn new workspaces from within a workspace.

## What you can do from this workspace

1. **Edit dev-installed packages** — make changes in `dev/<repo>` and open PRs to their upstream repos.
2. **Edit workbench infrastructure** — modify justfiles, skills, docs, or templates and open a PR to the workbench repo.

Up to **N+1 PRs** from a single workspace: 1 for the workbench + N for each dev-installed package.

## Repo directories

| Directory | Purpose |
|-----------|---------|
| `repos/` | Symlinks → read-only context. Browse source here, never edit. |
| `dev/` | Worktrees for editing. Dev-installed, push PRs from here. |
| `tmp/` | Worktrees for reading specific branches (`just dev checkout <repo> [branch]`). |

## General workflow

> Instructions in your prompt and PLAN.md always take precedence.

1. **Understand and reproduce the issue.** Prefer a failing test as your repro:
   - **Backend** (`.py`): write a failing `pytest` against `dev/<repo>`.
   - **Frontend** (`.ts`/`.tsx`/`.css`): if the repo has an E2E (Galata) suite, add a failing E2E test; otherwise add the best unit/integration test you can.

2. **Work on the fix.** After making changes:
   - **Frontend**: rebuild before running E2E tests — `(cd dev/<repo> && jlpm build)` (see the `rebuild-frontend` skill).
   - **Backend**: the editable install picks up `.py` changes automatically — just re-run the tests.

3. **Add test coverage.** At least unit/integration level. Add an E2E (Galata) test when the repo supports it.

4. **Verify.** Run from inside the dev repo (venv is already active):
   ```bash
   cd dev/<repo-name>
   pytest
   jlpm lint      # frontend repos
   mypy .         # if the repo uses mypy
   ```

5. **Notify the user.**
   - Done: `cmux notify --title "Done: <workspace>" --body "<brief summary>"`
   - Stuck: `cmux notify --title "Stuck: <workspace>" --body "<what's blocking>"`

## Git tips

- Workspace artifacts (`.venv/`, `repos/`, `dev/`, `tmp/`, `.workspace_info.json`, `pyproject.toml`) are gitignored.
- Only intentional workbench changes show in `git status`.
- For workbench PRs, commit and push from the worktree root.
- For package PRs, commit and push from inside `dev/<repo-name>/` (use `just dev ensure-fork <repo>` first).

## Quick Reference

| Situation | Where to look |
|-----------|---------------|
| Made frontend changes (`.ts`/`.tsx`/`.css`) | `.kiro/skills/rebuild-frontend/SKILL.md` |
| Made backend changes (`.py`) | Re-run `pytest` (editable install is live) |
| Need to dev-install another repo | `just dev add <repo>` then `just dev setup` |
| Need to open a pull request | `.kiro/skills/open-pr/SKILL.md` |
