# Workspace Agent Guide

You are a worker agent assigned to a task inside a workspace. Stay in your workspace. If you need another package, use `just add-dev`. If you need parallelism, use built-in subagent capabilities. Do NOT spawn new workspaces from within a workspace.

## General workflow

> Instructions in your prompt and PLAN.md always take precedence. This is just a sketch of a typical workflow.

1. **Understand and reproduce the issue.** Before writing code, make sure you understand the problem and have a way to verify your fix.
   - For frontend issues: check if the repo has E2E tests (`**/ui-tests/**/*`). If there are >1 existing E2E tests (not just boilerplate), add a failing E2E test to reproduce. Otherwise, use the cmux browser to reproduce visually.
   - For backend issues: try reproducing with a failing pytest first.
   - Start the server if it helps reproduce: `just start-server`
   - If you can't reliably reproduce (e.g., Windows-only issue on a macOS machine, Firefox-only issue in Safari/WKWebView), skip reproduction and note why. It's OK to ask for help.

2. **Work on the fix.** After making changes:
   - Frontend changes (`.ts`, `.tsx`, `.css`): use the `rebuild-frontend` skill
   - Backend changes (`.py`): run `just restart-server`
   - **Keep screenshots** in `screenshots/` — do NOT delete them. They serve as evidence of testing and may be used in the PR description later.

3. **Add test coverage.** Ensure at least unit/integration level tests cover your change. Skipping E2E tests is fine if the repo doesn't already have E2E test infrastructure to build off of.

4. **Verify with static analysis.** Run from inside the repo:
   ```bash
   just mypy
   just lint
   just pytest
   ```

5. **Notify the user.**
   - Done: `cmux notify --title "Done: <workspace>" --body "<brief summary>"`
   - Stuck: `cmux notify --title "Stuck: <workspace>" --body "<what's blocking>"`

## Sign-off steps (only when asked)

When the user asks you to sign off or clean up:

1. **Stop the server** — run `just stop-server` from the workspace root.

2. **Close extra surfaces** — close any surfaces created during the task (server terminal, browser):
   ```bash
   cmux close-surface --surface $SERVER_SURFACE
   cmux close-surface --surface $BROWSER_SURFACE
   ```

3. **Leave only the agent's own terminal** (the one running `kiro-cli chat`).

## Recipes

Run `just list-recipes` to see all available recipes.

### Workspace recipes

| Recipe | Description |
|--------|-------------|
| `start-server` | Start JupyterLab + open browser |
| `stop-server` | Stop the server |
| `restart-server` | Restart the server |
| `add-dev <repos>` | Clone + dev-install repos (comma-separated) |
| `add <pkgs>` | Add PyPI packages (comma-separated) |
| `build-all` | Build all dev repos |
| `enable-all-extensions` | Enable extensions for all dev repos |

### Repo recipes (run from inside a repo)

| Recipe | Description |
|--------|-------------|
| `build` | Rebuild frontend |
| `lint` | Run linters |
| `pytest` | Run tests |
| `mypy` | Run type checker |
| `ensure-fork` | Create GitHub fork |

## Quick Reference

| Situation | Where to look |
|-----------|---------------|
| Made frontend changes (`.ts`, `.tsx`, `.css`) | `.kiro/skills/rebuild-frontend/SKILL.md` |
| Made backend changes (`.py`) | Run `just restart-server` |
| Need to read server logs | `.kiro/skills/read-jupyter-server-logs/SKILL.md` |
| Need to interact with Jupyter Chat in the browser | `.kiro/skills/jupyter-chat-browser-use/SKILL.md` |
| Need to run JupyterLab commands programmatically | `.kiro/skills/run-jupyterlab-command/SKILL.md` |
| Need to open a pull request | `.kiro/skills/open-pr/SKILL.md` |
