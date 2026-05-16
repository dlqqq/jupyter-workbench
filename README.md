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

### Workbench recipes

Workbench recipes can be run from anywhere within the workbench.

| Recipe | Description |
|--------|-------------|
| `worktree-add <name> [--dev <repos...>] [--with <packages...>]` | Create a new worktree |
| `worktree-remove <name>` | Remove a worktree |
| `worktree-remove-all` | Remove all worktrees |
| `sync-recipes` | Sync justfile and scripts to all worktrees |

### Worktree recipes

Worktree recipes can be run from anywhere within a specific worktree
(`worktrees/<worktree-name>`).

| Recipe | Description |
|--------|-------------|
| `add-dev <repo>` | Clone + editable install a package |
| `add <pkgs...>` | Add PyPI packages (wrapper around `uv add`) |
| `sync` | Sync the venv (`uv sync`) |
| `start` | Launch JupyterLab |
| `start-cmux` | Start JupyterLab in a new tab + open browser to the right (cmux only) |
| `worktree-status` | List dev-installed packages |
| `enable-all-extensions` | Enable extensions for all dev repos |

### Repo recipes — run from inside a repo (`[no-cd]`)

Repository recipes can be run from anywhere within a repository checked out
inside of a worktree (e.g. `worktrees/jupyter-ai-issue-123/jupyter-ai-router`).

| Recipe | Description |
|--------|-------------|
| `build` | Rebuild frontend for the current repo |
| `enable-repo-extensions` | Enable server + lab extensions |
| `enable-repo-server-extensions` | Enable server extension only |
| `enable-repo-lab-extensions` | Enable lab extension only |

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

When `packages` is absent, defaults are:
- `name` = repo name with `-` replaced by `_`
- `parentDir` = `.`

### `.worktree_info`

Each worktree contains a `.worktree_info` file listing dev-installed repos (one
per line). This is managed automatically by `worktree-add` and `add-dev`.

## Architecture

```
jupyter-workbench/              ← workbench root
├── justfile
├── scripts/helpers.sh          ← shared bash functions
├── repos.json                  ← repo registry
├── repos.schema.json           ← JSON schema for repos.json
├── pyproject.toml              ← base deps (jupyterlab)
├── jupyter_server_config.py
└── worktrees/
    └── my-feature/             ← a worktree
        ├── .worktree_info      ← lists dev repos
        ├── .venv/
        ├── pyproject.toml      ← patched by uv
        ├── jupyter-ai-router/  ← cloned repo (editable)
        └── jupyter-chat/       ← cloned repo (editable)
```

## TODO

- [ ] Make spawned agent CLI configurable (support Codex, Claude Code, etc. in addition to Kiro)
