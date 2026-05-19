# jupyter-workbench

A lightweight Jupyter extension development orchestrator. Create parallel workspaces with only the packages you're actively editing — everything else installs from PyPI.

## Quick Start

```bash
# Create a workspace with specific packages for development
just workspace-add my-feature --dev jupyter-ai-acp-client jupyter-ai-persona-manager

# Start JupyterLab from the workspace
cd workspaces/my-feature
just server-start

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
| `workspace-add <name> [--dev <repos...>] [--with <packages...>]` | Create a new workspace |
| `workspace-remove <name>` | Remove a workspace |
| `workspace-remove-all` | Remove all workspaces |
| `get-workbench-root` | Echo the workbench root path |

### Workspace recipes (`workspace.just` → `justfile`)

| Recipe | Description |
|--------|-------------|
| `add-dev <repo>` | Clone + editable install a package |
| `add <pkgs...>` | Add PyPI packages (wrapper around `uv add`) |
| `sync` | Sync the venv (`uv sync`) |
| `server-start` | Start JupyterLab in a new tab + open browser |
| `server-stop` | Stop the JupyterLab server |
| `server-restart` | Restart the JupyterLab server |
| `server-status` | Check if a server is running |
| `workspace-status` | List dev-installed repos |
| `enable-all-extensions` | Enable extensions for all dev repos |
| `build-all` | Build all dev repos |
| `get-workspace-root` | Echo the workspace root path |

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
├── workspace.just               ← copied as justfile to workspaces
├── repo.just                   ← copied as justfile to repos
├── repos.json                  ← repo registry
├── pyproject.toml              ← base deps (jupyterlab)
├── jupyter_server_config.py
└── workspaces/
    └── my-feature/             ← a workspace
        ├── justfile            ← workspace.just copy
        ├── .workspace_info.json
        ├── .venv/
        ├── pyproject.toml
        ├── jupyter-ai-router/  ← cloned repo
        │   └── justfile        ← repo.just copy
        └── jupyter-chat/
            └── justfile        ← repo.just copy
```
