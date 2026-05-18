# jupyter-workbench

A lightweight Jupyter extension development orchestrator. Create parallel worktrees with only the packages you're actively editing — everything else installs from PyPI.

## Quick Start

```bash
# Create a worktree with specific packages for development
just worktree-add my-feature --dev jupyter-ai-acp-client jupyter-ai-persona-manager

# Start JupyterLab from the worktree
cd worktrees/my-feature
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
- Each worktree is a self-contained dev environment under `worktrees/`
- Only the packages you specify are cloned and installed as editable (via `uv add --editable --workspace`)
- All other dependencies come from PyPI
- Each worktree gets its own `.venv`

## Recipes

Recipes are split across 3 justfiles using `set fallback` so lower levels can call parent recipes.

### Workbench recipes (`justfile`)

| Recipe | Description |
|--------|-------------|
| `worktree-add <name> [--dev <repos...>] [--with <packages...>]` | Create a new worktree |
| `worktree-remove <name>` | Remove a worktree |
| `worktree-remove-all` | Remove all worktrees |
| `sync-workbench` | Sync justfiles and skills to all worktrees |
| `get-workbench-root` | Echo the workbench root path |

### Worktree recipes (`worktree.just` → `justfile`)

| Recipe | Description |
|--------|-------------|
| `add-dev <repo>` | Clone + editable install a package |
| `add <pkgs...>` | Add PyPI packages (wrapper around `uv add`) |
| `sync` | Sync the venv (`uv sync`) |
| `server-start` | Start JupyterLab in a new tab + open browser |
| `server-stop` | Stop the JupyterLab server |
| `server-restart` | Restart the JupyterLab server |
| `server-status` | Check if a server is running |
| `worktree-status` | List dev-installed repos |
| `enable-all-extensions` | Enable extensions for all dev repos |
| `build-all` | Build all dev repos |
| `get-worktree-root` | Echo the worktree root path |

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

### `.worktree_info.json`

Each worktree contains a `.worktree_info.json` tracking dev repos and server state. Managed automatically by recipes.

## Architecture

```
jupyter-workbench/              ← workbench root
├── justfile                    ← workbench recipes
├── worktree.just               ← copied as justfile to worktrees
├── repo.just                   ← copied as justfile to repos
├── repos.json                  ← repo registry
├── pyproject.toml              ← base deps (jupyterlab)
├── jupyter_server_config.py
└── worktrees/
    └── my-feature/             ← a worktree
        ├── justfile            ← worktree.just copy
        ├── .worktree_info.json
        ├── .venv/
        ├── pyproject.toml
        ├── jupyter-ai-router/  ← cloned repo
        │   └── justfile        ← repo.just copy
        └── jupyter-chat/
            └── justfile        ← repo.just copy
```
