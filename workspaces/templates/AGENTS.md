# Workspace Agent Guide

You are a worker agent assigned to a task inside a workspace. Your workspace is a **git worktree** of the workbench repo on branch `YYYYMMDD-<name>`. Your venv is already activated. Stay in your workspace. If you need another package, use `just dev`. Do NOT spawn new workspaces from within a workspace.

## What you can do from this workspace

1. **Edit dev-installed packages** — make changes in `dev/<repo>` and open PRs to their upstream repos.
2. **Edit workbench infrastructure** — modify the justfile, scripts, skills, docs, or templates and open a PR to the workbench repo.

Up to **N+1 PRs** from a single workspace: 1 for the workbench + N for each dev-installed package.

## Repo directories

| Directory | Purpose |
|-----------|---------|
| `repos/` | Symlinks → read-only context. Browse source here, never edit. |
| `dev/` | Worktrees for editing. Dev-installed, push PRs from here. |
| `tmp/` | Worktrees for reading specific branches (`just checkout-repo`). |

## General workflow

> Instructions in your prompt and PLAN.md always take precedence.

1. **Understand and reproduce the issue.**
   - For frontend issues: check for E2E tests (`**/ui-tests/**/*`). Add a failing test or reproduce visually.
   - For backend issues: try a failing pytest first.
   - Start the server if needed: `just start-server`

2. **Work on the fix.** After making changes:
   - Frontend changes (`.ts`, `.tsx`, `.css`): use the `rebuild-frontend` skill
   - Backend changes (`.py`): run `just restart-server`
   - **Keep screenshots** in `screenshots/` — do NOT delete them.

3. **Add test coverage.** At least unit/integration level tests.

4. **Verify with static analysis.** Run from inside the dev repo:
   ```bash
   cd dev/<repo-name>
   mypy .
   jlpm lint
   pytest
   ```

5. **Notify the user.**
   - Done: `cmux notify --title "Done: <workspace>" --body "<brief summary>"`
   - Stuck: `cmux notify --title "Stuck: <workspace>" --body "<what's blocking>"`

## Git tips

- Workspace artifacts (`.venv/`, `repos/`, `dev/`, `tmp/`, `.workspace_info.json`) are gitignored.
- Only intentional workbench changes show in `git status`.
- For workbench PRs, commit and push from the worktree root.
- For package PRs, commit and push from inside `dev/<repo-name>/`.

## Sign-off steps (only when asked)

1. `just stop-server`
2. Close extra surfaces (server terminal, browser)
3. Leave only the agent's own terminal.

## Quick Reference

| Situation | Where to look |
|-----------|---------------|
| Made frontend changes | `.kiro/skills/rebuild-frontend/SKILL.md` |
| Made backend changes | Run `just restart-server` |
| Need to read server logs | `.kiro/skills/read-jupyter-server-logs/SKILL.md` |
| Need to interact with Jupyter Chat | `.kiro/skills/jupyter-chat-browser-use/SKILL.md` |
| Need to run JupyterLab commands | `.kiro/skills/run-jupyterlab-command/SKILL.md` |
| Need to open a pull request | `.kiro/skills/open-pr/SKILL.md` |
