# Agents

## About this project

jupyter-workbench is a Jupyter extension development orchestrator. It manages parallel worktrees where developers edit specific packages while the rest install from PyPI.

## For orchestrator agents (running outside a worktree)

You manage the workbench. Your job is to create worktrees for new tasks and spawn agent sessions to work on them. Use the `spawn-agent` skill when the user gives you a GitHub issue to delegate. One worktree per task.

## For worker agents (running inside a worktree)

You are assigned to a task. Stay in your worktree. If you need another package, use `just add-dev`. If you need parallelism, use built-in subagent capabilities. Do NOT spawn new worktrees from within a worktree.

### General workflow

> Instructions in your prompt and PLAN.md always take precedence. This is just a sketch of a typical workflow.

1. **Understand and reproduce the issue.** Before writing code, make sure you understand the problem and have a way to verify your fix.
   - For frontend issues: check if the repo has E2E tests (`**/ui-tests/**/*`). If there are >1 existing E2E tests (not just boilerplate), add a failing E2E test to reproduce. Otherwise, use the cmux browser to reproduce visually.
   - For backend issues: try reproducing with a failing pytest first.
   - Start the server if it helps reproduce: `just server-start`
   - If you can't reliably reproduce (e.g., Windows-only issue on a macOS machine, Firefox-only issue in Safari/WKWebView), skip reproduction and note why. It's OK to ask for help.

2. **Work on the fix.** After making changes:
   - Frontend changes (`.ts`, `.tsx`, `.css`): use the `rebuild-frontend` skill
   - Backend changes (`.py`): run `just server-restart`
   - **Keep screenshots** in `screenshots/` — do NOT delete them. They serve as evidence of testing and may be used in the PR description later.

3. **Add test coverage.** Ensure at least unit/integration level tests cover your change. Skipping E2E tests is fine if the repo doesn't already have E2E test infrastructure to build off of.

4. **Verify with static analysis.** Run from inside the repo:
   ```bash
   just mypy
   just lint
   just pytest
   ```

5. **Notify the user.**
   - Done: `cmux notify --title "Done: <worktree>" --body "<brief summary>"`
   - Stuck: `cmux notify --title "Stuck: <worktree>" --body "<what's blocking>"`

### Sign-off steps (only when asked)

When the user asks you to sign off or clean up:

1. **Stop the server** — run `just server-stop` from the worktree root.

2. **Close extra surfaces** — close any surfaces created during the task (server terminal, browser):
   ```bash
   cmux close-surface --surface $SERVER_SURFACE
   cmux close-surface --surface $BROWSER_SURFACE
   ```

3. **Leave only the agent's own terminal** (the one running `kiro-cli chat`).

## Recipe Groups

Everything in the workbench uses `just`, a command runner. Recipes are split across 3 justfiles, each scoped to its directory level. Lower-level justfiles use `set fallback` to access parent recipes.

| File | Location | Groups | Examples |
|------|----------|--------|---------|
| `justfile` | Workbench root | `[workbench]` | `worktree-add`, `get-workbench-root` |
| `worktree.just` → `justfile` | Worktree root | `[worktree]`, `[worktree-server]` | `add-dev`, `server-start`, `build-all`, `get-worktree-root` |
| `repo.just` → `justfile` | Repo root | `[repo]` | `build`, `lint`, `pytest`, `ensure-fork` |

- **Fallback**: repo recipes can call worktree recipes, worktree recipes can call workbench recipes.
- **Path resolution**: each justfile uses `{{ justfile_directory() }}` as its root. Call `just get-worktree-root` or `just get-workbench-root` from lower levels.

### Usage examples

```bash
# Workbench recipe (from workbench root)
just worktree-add my-feature --dev jupyter-ai-router

# Worktree recipe (from inside the worktree)
just server-start

# Repo recipe (from inside a repo)
just build
just lint
```

Run `just --list --unsorted` to see all available recipes (including fallback parents).

## Quick Reference

| Situation | Where to look |
|-----------|---------------|
| Made frontend changes (`.ts`, `.tsx`, `.css`) | `.kiro/skills/rebuild-frontend/SKILL.md` |
| Made backend changes (`.py`) | Run `just server-restart` |
| Need to read server logs | `.kiro/skills/read-jupyter-server-logs/SKILL.md` |
| Need to interact with Jupyter Chat in the browser | `.kiro/skills/jupyter-chat-browser-use/SKILL.md` |
| Need to run JupyterLab commands programmatically | `.kiro/skills/run-jupyterlab-command/SKILL.md` |
| Need to open a pull request | `.kiro/skills/open-pr/SKILL.md` |
| Need to spawn a new agent session for an issue | `.kiro/skills/spawn-agent/SKILL.md` (workbench root only) |
| Need to add a repo not listed in `repos.json` | `CONTRIBUTING.md` |
| Need to add or modify a justfile recipe | `CONTRIBUTING.md` |
| Need to understand workbench internals (justfile split, `.worktree_info.json`) | `CONTRIBUTING.md` |

## Modifying recipes or workbench internals

See [CONTRIBUTING.md](CONTRIBUTING.md).
