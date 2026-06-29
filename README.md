# jupyter-workbench

A lightweight Jupyter extension development orchestrator. Create parallel workspaces with only the packages you're actively editing — everything else installs from PyPI.

## Quick Start

```bash
# Pre-clone all repos (one-time setup)
just repos clone

# Create a workspace (fast scaffold)
just ws create my-feature

# Set it up: dev-install packages, sync the venv, enable extensions
cd workspaces/my-feature
just dev add jupyter-ai-acp-client,jupyter-ai-persona-manager
just dev setup

# Or do it all in one shot via --then (runs inside the new cmux workspace)
just ws create my-feature --then 'just dev add jupyter-ai-router && just dev setup && just spawn-agent "fix issue 42"'

# Start JupyterLab
just start

# Check out a branch for reading (without dev-installing)
just dev checkout jupyter-chat feature-branch
```

## How It Works

- The workbench is the top-level orchestrator repo
- Each workspace is a **git worktree** on branch `YYYYMMDD-<name>`
- Repos are pre-cloned at the workbench root (`repos/`) and shared across workspaces
- Each workspace has 3 repo directories:
  - `repos/` — symlinks to workbench `repos/` (read-only context for agents)
  - `dev/` — worktrees from source repos (editable, dev-installed)
  - `tmp/` — worktrees for reading specific branches
- From a single workspace, you can open up to **N+1 PRs**: 1 for the workbench itself + N for each dev-installed package

## Recipes

Recipes are organized into modules. Run `just --list --list-submodules` to see everything.

### Workbench

| Recipe | Description |
|--------|-------------|
| `just repos clone` | Clone/fetch all repos into workbench `repos/` |
| `just ws create <name> [--then '<cmds>']` | Create a new workspace (fast scaffold; runs `<cmds>` in the new cmux workspace) |
| `just ws rm <name>` | Remove a workspace (instant; deletes files in the background) |
| `just ws cleanup` | Delete all workspaces not open in cmux |

### Workspace

| Recipe | Description |
|--------|-------------|
| `just start` | Start server and open browser |
| `just dev add <repos>` | Create worktree(s) under `dev/` + add as editable member(s), no sync (comma-separated) |
| `just dev setup [--with=<pkgs>]` | `uv sync` + enable extensions for all `dev/` repos (+ optional PyPI packages) |
| `just dev remove <repo>` | Remove a dev-installed repo (worktree + pyproject member) |
| `just dev checkout <repo> [branch]` | Create worktree under `tmp/` for reading a branch |
| `just add <pkgs>` | Add PyPI packages (comma-separated) |
| `just sync` | Sync the venv (`uv sync`) |
| `just dev enable-extensions <repo>` | Enable extensions for a dev repo |
| `just dev ensure-fork <repo>` | Create a GitHub fork for a dev repo |
| `just spawn-agent <prompt>` | Spawn an agent session with a prompt (activates venv) |
| `just stop-agent` | Stop the agent session |
| `just close` | Stop agent + server, close cmux workspace |
| `just server start` / `stop` / `restart` | Server management |
| `just browser open` / `close` / `refresh` | Browser management |
| `just browser eval <script> [args...]` | Run a JS script in the browser |

## Architecture

```
jupyter-workbench/                  ← workbench root (main checkout)
├── justfile                        ← top-level recipes + module imports
├── server.just                     ← server module
├── browser.just                    ← browser module
├── repos.json                      ← repo registry
├── repos/                          ← pre-cloned source repos (shared, gitignored)
│   ├── justfile                    ← repos module
│   ├── jupyter-ai/
│   ├── jupyter-chat/
│   └── ...
├── dev/                            ← (workspace-level: dev-installed worktrees)
│   └── justfile                    ← dev module
├── scripts/                        ← JS scripts for browser-eval
├── tmp/                            ← scratch space
└── workspaces/
    ├── justfile                    ← ws module
    ├── templates/
    └── my-feature/                 ← workspace (git worktree on branch 20260624-my-feature)
        ├── .workspace_info.json
        ├── .venv/
        ├── repos/                  ← symlinks → ../../repos/* (read-only context)
        │   ├── jupyter-ai -> ../../repos/jupyter-ai
        │   └── ...
        ├── dev/                    ← worktrees (editable, dev-installed)
        │   └── jupyter-ai-router/
        └── tmp/                    ← worktrees (branch checkouts for reading)
            └── jupyter-chat/
```
