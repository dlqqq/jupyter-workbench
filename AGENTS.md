# Agents

<!-- This AGENTS.md is for orchestrator agents working from the main workbench root.
     Workspace worker agents use the AGENTS.md in workspaces/templates/AGENTS.md instead. -->

jupyter-workbench is a Jupyter extension development orchestrator. It manages parallel workspaces where developers edit specific packages while the rest install from PyPI. Each workspace is a git worktree of the workbench repo, so agents can also modify workbench infrastructure (recipes, scripts, templates) and open PRs for both the workbench and the dev-installed packages.

## Orchestrator (main workbench root)

You manage the workbench. Your job is to create workspaces for new tasks and spawn agent sessions to work on them. Use the `spawn-agent` skill when the user gives you a GitHub issue to delegate. One workspace per task.

### Recipes

| Recipe | Description |
|--------|-------------|
| `clone-all` | Pre-clone/fetch all repos (run once or to update) |
| `create-workspace <name> [--dev=<repos>] [--with=<pkgs>] [--spawn-agent] [--prompt=<text>]` | Create a new workspace (non-blocking) |
| `cleanup` | Delete all workspaces not open in cmux (human-only, requires interactive confirmation) |

## Workspace worker (inside `workspaces/<name>/`)

You are working in a workspace. Your workspace is a git worktree on branch `YYYYMMDD-<name>`. You can:

1. **Edit dev-installed packages** — make changes in `dev/<repo>` and open PRs to their upstream repositories.
2. **Edit workbench infrastructure** — modify justfiles, scripts, skills, docs, or templates and open a PR to the workbench repo itself.

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
- Workspace artifacts (`.venv/`, `repos/`, `dev/`, `tmp/`, `.workspace_info.json`) are gitignored

## Justfile Architecture

All recipes live in a single `justfile` at the repo root, organized by `[group]`:

| Group | Purpose |
|-------|---------|
| `workbench` | Workspace lifecycle |
| `workspace` | Operations inside a workspace |
| `workspace-server` | JupyterLab server management |
| `workspace-browser` | Browser automation |
| `workspace-jupyter-chat` | Jupyter Chat helpers |
| `workspace-notebook` | Notebook automation |

Run `just list-recipes` to see all available recipes.

## Browser Eval Scripts

JS scripts in `scripts/` can be run via `just browser-eval <script-name> [args...]`.

## Modifying recipes or workbench internals

See [CONTRIBUTING.md](CONTRIBUTING.md).
