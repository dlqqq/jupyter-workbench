# jupyter-workbench

A lightweight Jupyter extension development orchestrator. Create parallel worktrees with only the packages you're actively editing — everything else installs from PyPI.

## Quick Start

```bash
# Create a worktree with specific packages for development
just worktree-add my-feature --dev jupyter-ai-acp-client jupyter-ai-persona-manager

# Start JupyterLab from the worktree
cd worktrees/my-feature
just start

# Add another package later
just add-dev jupyter-ai-router

# Add a PyPI-only dependency
just add httpx

# Switch a branch before building
cd jupyter-ai-acp-client && git checkout my-branch
just build
```

## How It Works

- The workbench is the top-level orchestrator repo
- Each worktree is a self-contained dev environment under `worktrees/`
- Only the packages you specify are cloned and installed as editable (via `uv add --editable --workspace`)
- All other dependencies come from PyPI
- Each worktree gets its own `.venv`

## Recipes

### Workbench recipes — can be run anywhere within the workbench

| Recipe | Description |
|--------|-------------|
| `worktree-add <name> [--dev <repos...>] [--with <packages...>]` | Create a new worktree |
| `worktree-remove <name>` | Remove a worktree |

### Worktree recipes — can be run anywhere within a worktree

| Recipe | Description |
|--------|-------------|
| `add-dev <repos...>` | Clone + editable install additional packages |
| `add <pkgs...>` | Add a PyPI package (thin wrapper around `uv add`) |
| `start` | Launch JupyterLab |
| `worktree-status` | List dev-installed packages |

### Repo recipes — can be run from inside a repo being developed in a worktree

| Recipe | Description |
|--------|-------------|
| `build` | Rebuild frontend for the current repo |

## Adding Repos

Edit `repos.json` to add new repo name → git URL mappings.

## Special Cases

- `jupyter-chat`: The Python package lives at `jupyter-chat/python/jupyterlab-chat/`. The recipes handle this automatically.
