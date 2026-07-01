# jupyter-workbench

**Jupyter Workbench v0.2**

A lightweight Jupyter extension development orchestrator. Create parallel workspaces with only the packages you're actively editing — everything else installs from PyPI.

> **Status & direction.** Server/browser interaction currently goes through
> [cmux](https://github.com/cmux) (macOS-oriented). This is transitional: the
> plan for v0.2 is to migrate verification onto JupyterLab's
> [Galata](https://github.com/jupyterlab/jupyterlab/tree/main/galata) end-to-end
> framework (built on Playwright) exclusively. That removes the cmux dependency
> for testing and lets the workbench — and the agents it spawns — run on Linux
> and in remote/CI environments. The `server` and `browser` recipe modules below
> are **deprecated** and will be replaced by Galata-based flows.

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

# Or script the provisioning: write workspaces/my-feature/setup.sh with the
# chain (dev add → dev setup → ws _launch-agent) plus a PROMPT.md, then let
# ws spawn run it in the cmux workspace. Both are files, so no command/prompt
# text crosses a shell-quoting boundary. (Usually an orchestrator agent does
# this — see below.)
just ws spawn my-feature

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

## Configuration

`workbench-config.json` (at the workbench root, version-controlled) holds
workbench-wide settings. Today it defines `agent-cmd` — the CLI launched for the
workspace agent (by `ws _launch-agent`, at the end of `setup.sh`), with
`PROMPT.md`'s contents appended as the final argument:

```json
{ "agent-cmd": "claude --permission-mode auto" }
```

Swap it for another agent CLI as long as it takes the prompt as a trailing
positional argument, e.g. `"kiro-cli chat --agent dlq -a"` or `"codex"`.

## Recipes

Recipes are organized into modules. Run `just --list --list-submodules` to see everything.

### Workbench

| Recipe | Description |
|--------|-------------|
| `just repos clone` | Clone/fetch all repos into workbench `repos/` |
| `just ws create <name>` | Create a new workspace (fast scaffold only) |
| `just ws spawn <name>` | Run the workspace's `setup.sh` in its cmux workspace to provision + launch the agent (needs `setup.sh` + `PROMPT.md`) — _agent-invoked_ |
| `just ws rm <name>` | Remove a workspace (instant; deletes files in the background) |
| `just ws cleanup` | Delete all workspaces not open in cmux |

> `ws spawn` is normally driven by an orchestrator agent (see the
> `spawn-workspace-agent` skill), not run by hand. `ws create` + writing
> `setup.sh`/`PROMPT.md` are the human/orchestrator entry points. `setup.sh` ends
> in `just ws _launch-agent`, the private recipe that launches the agent CLI.

### Workspace

| Recipe | Description |
|--------|-------------|
| `just dev add <repos>` | Create worktree(s) under `dev/` + add as editable member(s), no sync (comma-separated) |
| `just dev setup [--with=<pkgs>]` | `uv sync` + enable extensions for all `dev/` repos (+ optional PyPI packages) |
| `just dev remove <repo>` | Remove a dev-installed repo (worktree + pyproject member) |
| `just dev checkout <repo> [branch]` | Create worktree under `tmp/` for reading a branch |
| `just add <pkgs>` | Add PyPI packages (comma-separated) |
| `just sync` | Sync the venv (`uv sync`) |
| `just dev enable-extensions <repo>` | Enable extensions for a dev repo |
| `just dev ensure-fork <repo>` | Create a GitHub fork for a dev repo |
| `just stop-agent` | Stop the agent session |
| `just close` | Stop agent + server, close cmux workspace |

### Deprecated (cmux-based, to be replaced by Galata)

These still work on macOS via cmux but are slated for removal once Galata-based
flows land. **Do not build new automation on them.**

| Recipe | Description |
|--------|-------------|
| `just start` | Start server and open browser |
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
├── scripts/                        ← JS scripts for browser-eval (deprecated)
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
