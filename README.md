# jupyter-workbench

A lightweight Jupyter extension development orchestrator. Create parallel workspaces with only the packages you're actively editing — everything else installs from PyPI.

## Quick Start

```bash
# Create a workspace with specific packages for development
just add-workspace my-feature --dev=jupyter-ai-acp-client,jupyter-ai-persona-manager

# Start JupyterLab from the workspace
cd workspaces/my-feature
just start-server

# Add another package later
just add-dev jupyter-ai-router

# Add a PyPI-only dependency
just add httpx

# Rebuild a single repo's frontend after changes
cd jupyter-ai-acp-client
just build
```

## How It Works

- The workbench is the top-level orchestrator repo
- Each workspace is a self-contained dev environment under `workspaces/`
- Only the packages you specify are cloned and installed as editable (via `uv add --editable --workspace`)
- All other dependencies come from PyPI
- Each workspace gets its own `.venv`

## Recipes

Recipes are split across 3 justfiles using `set fallback` so lower levels can call parent recipes.

### Workbench recipes (`justfile`)

| Recipe | Description |
|--------|-------------|
| `add-workspace <name> [--dev=<repos>] [--with=<pkgs>] [--spawn-agent] [--prompt=<text>]` | Create a new workspace (non-blocking) |
| `cleanup` | Delete all workspaces/worktrees not open in cmux |
| `add-worktree <name>` | Create a workbench worktree (git branch) |
| `remove-worktree <name> [--force]` | Remove a workbench worktree |
| `get-workbench-root` | Echo the workbench root path |

### Workspace recipes (`workspace.just` → `justfile`)

| Recipe | Description |
|--------|-------------|
| `add-dev <repos>` | Clone + editable install repos (comma-separated) |
| `add <pkgs>` | Add PyPI packages (comma-separated) |
| `sync` | Sync the venv (`uv sync`) |
| `start-server` | Start JupyterLab in a new tab + open browser |
| `stop-server` | Stop the JupyterLab server |
| `restart-server` | Restart the JupyterLab server |
| `server-status` | Check if a server is running |
| `spawn-agent` | Spawn an agent session from `.workspace_info.json` prompt |
| `stop-agent` | Stop the agent session |
| `close-workspace` | Stop agent + server, close cmux workspace |
| `workspace-status` | List dev-installed repos |
| `enable-all-extensions` | Enable extensions for all dev repos |
| `build-all` | Build all dev repos |
| `get-workspace-root` | Echo the workspace root path |
| `setup-workspace` | Clone repos, install, enable extensions (runs automatically) |

### Repo recipes (`repo.just` → `justfile`)

| Recipe | Description |
|--------|-------------|
| `build` | Rebuild frontend for the current repo |
| `lint` | Run frontend linters |
| `pytest` | Run pytest |
| `mypy` | Run mypy |
| `enable-repo-extensions` | Enable server + lab extensions |
| `ensure-fork` | Create a GitHub fork and add as remote |

## Configuration

### `repos.json`

Maps repo names to git URLs and optional package metadata:

```json
{
  "jupyter-ai-router": { "url": "git@github.com:jupyter-ai-contrib/jupyter-ai-router.git" },
  "jupyter-chat": {
    "url": "git@github.com:jupyterlab/jupyter-chat.git",
    "packages": [
      { "name": "jupyterlab_chat", "parentDir": "python/jupyterlab-chat" }
    ]
  }
}
```

### `.workspace_info.json`

Each workspace contains a `.workspace_info.json` tracking dev repos and server state. Managed automatically by recipes.

## Architecture

```
jupyter-workbench/              ← workbench root
├── justfile                    ← workbench recipes
├── workspace.just              ← symlinked as justfile to workspaces
├── repo.just                   ← symlinked as justfile to repos
├── repos.json                  ← repo registry
├── workspaces/
│   ├── templates/              ← files copied into new workspaces
│   │   ├── AGENTS.md
│   │   ├── pyproject.toml
│   │   └── jupyter_server_config.py
│   └── my-feature/            ← a workspace (plain directory)
│       ├── justfile            ← symlink → workspace.just
│       ├── .workspace_info.json
│       ├── .venv/
│       └── jupyter-ai-router/
│           └── justfile        ← symlink → repo.just
└── worktrees/
    └── fix-recipes/            ← a workbench worktree (git branch)
        ├── justfile            ← workbench justfile (from git)
        ├── workspace.just
        └── repo.just
```
