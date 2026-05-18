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
   - Start the server if it helps reproduce: `just start-cmux`
   - If you can't reliably reproduce (e.g., Windows-only issue on a macOS machine, Firefox-only issue in Safari/WKWebView), skip reproduction and note why. It's OK to ask for help.

2. **Work on the fix.** After making changes:
   - Frontend changes (`.ts`, `.tsx`, `.css`): use the `rebuild-frontend` skill
   - Backend changes (`.py`): use the `restart-jupyter-server` skill

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

## Recipe Groups

Everything in the workbench uses `just`, a command runner. Recipes are organized into 3 categories based on their scope:

| Group | Where to run | Examples |
|-------|-------------|---------|
| **workbench** | Workbench root | `worktree-add`, `worktree-remove`, `sync-worktrees` |
| **worktree** | Worktree root | `add-dev`, `start`, `start-cmux`, `build-all`, `enable-all-extensions` |
| **repo** | Inside a repo | `build`, `jlpm`, `enable-repo-extensions` |

- **Workbench recipes** can be run from anywhere inside the workbench (including from within worktrees).
- **Worktree recipes** can only be run from within a worktree (`worktrees/<name>/`).
- **Repo recipes** can only be run from inside a repo within a worktree.

### Usage examples

```bash
# Workbench recipe (from anywhere in the workbench)
just worktree-add my-feature --dev jupyter-ai-router

# Worktree recipe (from inside the worktree)
just start

# Worktree recipe (from the workbench root)
just worktrees/my-feature/start

# Repo recipe (from inside a repo)
(cd worktrees/my-feature/jupyter-ai-router && just build)
```

Run `just --list --unsorted` to see all available recipes grouped.

## Quick Reference

| Situation | Where to look |
|-----------|---------------|
| Made frontend changes (`.ts`, `.tsx`, `.css`) | `.kiro/skills/rebuild-frontend/SKILL.md` |
| Made backend changes (`.py`) | `.kiro/skills/restart-jupyter-server/SKILL.md` |
| Need to read server logs | `.kiro/skills/read-jupyter-server-logs/SKILL.md` |
| Need to interact with Jupyter Chat in the browser | `.kiro/skills/jupyter-chat-browser-use/SKILL.md` |
| Need to run JupyterLab commands programmatically | `.kiro/skills/run-jupyterlab-command/SKILL.md` |
| Need to spawn a new agent session for an issue | `.kiro/skills/spawn-agent/SKILL.md` (workbench root only) |
| Need to add a repo not listed in `repos.json` | `CONTRIBUTING.md` |
| Need to add or modify a justfile recipe | `CONTRIBUTING.md` |
| Need to understand workbench internals (helpers, `.worktree_info`) | `CONTRIBUTING.md` |

## Modifying recipes or workbench internals

See [CONTRIBUTING.md](CONTRIBUTING.md).
