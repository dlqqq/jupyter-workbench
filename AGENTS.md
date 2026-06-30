# Agents

<!-- This AGENTS.md is for orchestrator agents working from the main workbench root.
     Workspace worker agents use the AGENTS.md in workspaces/templates/AGENTS.md instead. -->

jupyter-workbench is a Jupyter extension development orchestrator (v0.2). It manages parallel workspaces where developers edit specific packages while the rest install from PyPI. Each workspace is a git worktree of the workbench repo, so agents can also modify workbench infrastructure (recipes, skills, docs, templates) and open PRs for both the workbench and the dev-installed packages.

## Orchestrator (main workbench root)

You manage the workbench. Your job is to create workspaces for new tasks and spawn agent sessions to work on them. Use the `spawn-agent` skill when the user gives you a GitHub issue to delegate. One workspace per task.

### Recipes

| Recipe | Description |
|--------|-------------|
| `just repos clone` | Pre-clone/fetch all repos into `repos/` (run once or to update) |
| `just ws create <name> [--then '<cmds>']` | Create a workspace (fast scaffold); runs `<cmds>` in the new cmux workspace |
| `just ws rm <name>` | Remove a workspace (instant; background delete) |
| `just ws cleanup` | Delete all workspaces not open in cmux (human-only, interactive confirmation) |

To delegate an issue, use the `spawn-agent` skill, which composes:
`just ws create <name> --then 'just dev add <repos> && just dev setup && just spawn-agent "<prompt>"'`.

## Workspace worker (inside `workspaces/<name>/`)

You are working in a workspace — a git worktree on branch `YYYYMMDD-<name>`, with the venv already activated. You can:

1. **Edit dev-installed packages** — make changes in `dev/<repo>` and open PRs to their upstream repositories.
2. **Edit workbench infrastructure** — modify justfiles, skills, docs, or templates and open a PR to the workbench repo itself.

Up to N+1 PRs from a single workspace (1 for the workbench, N for each dev-installed package).

### Repo directories

| Directory | Purpose |
|-----------|---------|
| `repos/` | Symlinks to source repos — read-only context, never edit |
| `dev/` | Worktrees for editing — dev-installed, push PRs from here |
| `tmp/` | Worktrees for reading specific branches |

### Workflow

See `workspaces/templates/AGENTS.md` for the full worker agent workflow.

### Rules

- Do NOT modify other workspaces or the main checkout
- Do NOT edit files in `repos/` — they're shared symlinks
- Stay on your branch for workbench changes
- Workspace artifacts (`.venv/`, `repos/`, `dev/`, `tmp/`, `.workspace_info.json`, `pyproject.toml`) are gitignored

## Justfile Architecture

Recipes are organized into modules (`mod` in the root `justfile`):

| Module | Purpose |
|--------|---------|
| `repos` | Pre-clone/fetch source repos (`just repos clone`) |
| `dev` | Per-workspace repo management (`add`, `setup`, `remove`, `checkout`, `ensure-fork`) |
| `ws` | Workspace lifecycle (`create`, `rm`, `cleanup`) |

Run `just --list --list-submodules` to see all recipes.

> **Deprecated:** the `server` and `browser` modules are cmux/macOS-based and are
> being replaced by JupyterLab's Galata (Playwright) E2E framework. Do not use
> them in new automation.

## Tests

Workbench recipes are covered by bats tests under `workbench-tests/`. Run them with
`just workbench-tests run-all` (or `run <file>`). Add coverage when you change recipes.

## Modifying recipes or workbench internals

See [CONTRIBUTING.md](CONTRIBUTING.md).
