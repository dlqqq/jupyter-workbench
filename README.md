# jupyter-workbench

A lightweight Jupyter extension development orchestrator. Create parallel worktrees with only the packages you're actively editing — everything else installs from PyPI.

## Quick Start

```bash
# Create a worktree with specific packages for development
just worktree-create my-feature jupyter-ai-acp-client jupyter-ai-persona-manager

# Start JupyterLab from the worktree
cd worktrees/my-feature
just start

# Add another package later
just worktree-add jupyter-ai-router
```

## How It Works

- The workbench is the top-level orchestrator repo
- Each worktree is a self-contained dev environment under `worktrees/`
- Only the packages you specify are cloned and installed as editable
- All other dependencies come from PyPI
- Each worktree gets its own `.venv`

## Recipes

| Recipe | Context | Description |
|--------|---------|-------------|
| `worktree-create <name> <repos...>` | root | Create a new worktree with specified packages |
| `worktree-add <repos...>` | worktree | Add packages to an existing worktree |
| `start` | worktree | Launch JupyterLab |
| `build` | worktree | Rebuild frontend for all dev packages |
| `worktree-status` | worktree | List dev-installed packages |

## Adding Repos

Edit `repos.json` to add new repo name → git URL mappings.
