# jupyter-workbench

## Problem Statement

The current `jupyter-ai-devrepo` requires cloning all 13 submodules (~4.7GB) to develop any single extension. We want a lightweight orchestrator repo ("workbench") where you only clone the packages you're actively editing, with the rest installed from PyPI.

## Design Decisions

- No git submodules — uses a `repos.json` lookup table instead
- Worktrees under `./worktrees/<name>/` for parallel dev environments
- Repos identified by repo name (e.g., `jupyter-ai-acp-client`)
- Dev packages distinguished by comment markers in `pyproject.toml`
- `jupyter-chat` hardcoded as a special multi-package case (package at `jupyter-chat/python/jupyterlab-chat/`)
- JupyterLab always installed as a base dependency
- Detached HEAD worktrees (no branching the orchestrator)
- Automatic frontend build + extension enabling
- `.is_worktree` marker file to identify worktree directories
- One justfile that works in both contexts (root for `subtree-create`, worktree for `subtree-add`/`start`/etc.)

## Structure

```
jupyter-workbench/                  ← the workbench (orchestrator repo)
├── .gitignore
├── README.md
├── justfile
├── repos.json                      ← repo name → git URL lookup table
├── pyproject.toml                  ← base deps (jupyterlab, pip)
├── jupyter_server_config.py
└── worktrees/                      ← gitignored
    └── <name>/                     ← a worktree (disposable dev env)
        ├── .is_worktree            ← marker file
        ├── .venv/
        ├── pyproject.toml          ← patched with workspace sources
        ├── jupyter-ai-acp-client/  ← git clone (editable)
        └── ...
```

## Recipes

- **`subtree-create <name> <repos...>`** — creates worktree, clones repos, patches pyproject.toml, uv sync, builds frontend, enables extensions. Full working environment in one command.
- **`subtree-add <repos...>`** — adds repos to an existing worktree (same steps). Only works inside a worktree.
- **`start`** — launches JupyterLab with the workbench server config.
- **`build`** — rebuilds frontend for all workspace packages in the worktree.
- **`subtree-status`** — lists which packages are dev-installed in the current worktree.

## Tasks

### Task 1: Initialize the repo

Create the repo at `~/workplace/jupyter-workbench` with `git init`, `.gitignore` (worktrees/, .venv, node_modules, .env, *.egg-info), and a README.

### Task 2: Create `repos.json` lookup table

JSON file mapping repo names to git clone URLs:

```json
{
  "jupyter-ai": "git@github.com:jupyterlab/jupyter-ai.git",
  "jupyter-ai-acp-client": "git@github.com:jupyter-ai-contrib/jupyter-ai-acp-client.git",
  "jupyter-ai-chat-commands": "git@github.com:jupyter-ai-contrib/jupyter-ai-chat-commands.git",
  "jupyter-ai-jupyternaut": "git@github.com:jupyter-ai-contrib/jupyter-ai-jupyternaut.git",
  "jupyter-ai-litellm": "git@github.com:jupyter-ai-contrib/jupyter-ai-litellm.git",
  "jupyter-ai-magic-commands": "git@github.com:jupyter-ai-contrib/jupyter-ai-magic-commands.git",
  "jupyter-ai-persona-manager": "git@github.com:jupyter-ai-contrib/jupyter-ai-persona-manager.git",
  "jupyter-ai-router": "git@github.com:jupyter-ai-contrib/jupyter-ai-router.git",
  "jupyter-ai-tools": "git@github.com:jupyter-ai-contrib/jupyter-ai-tools.git",
  "jupyter-chat": "git@github.com:jupyterlab/jupyter-chat.git",
  "jupyter-server-documents": "git@github.com:jupyter-ai-contrib/jupyter-server-documents.git",
  "jupyter-server-mcp": "git@github.com:jupyter-ai-contrib/jupyter-server-mcp.git",
  "jupyterlab-commands-toolkit": "git@github.com:jupyter-ai-contrib/jupyterlab-commands-toolkit.git"
}
```

### Task 3: Create base `pyproject.toml`

Minimal pyproject with JupyterLab as the only real dependency:

```toml
[project]
name = "jupyter-workbench"
version = "0.0.0"
requires-python = ">=3.10, <3.14"
dependencies = [
    "pip",
    "jupyterlab>=4",
]

[tool.uv.workspace]
members = []
```

The `members` list and `[tool.uv.sources]` will be patched per-worktree by the recipes.

### Task 4: Create `jupyter_server_config.py`

Server config for MCP and YRoom settings:

```python
c.MCPExtensionApp.mcp_port = 18741
c.MCPExtensionApp.mcp_name = "Jupyter MCP Server"
c.YRoomManager.auto_free_interval = 1
c.YRoomManager.show_gc_debug = True
c.YRoom.inactivity_timeout = 1
```

### Task 5: Implement `subtree-create` recipe

`just subtree-create <name> <repos...>`:

1. Validate each repo name against `repos.json` using `jq`
2. Run `git worktree add --detach ./worktrees/<name>`
3. Write `.is_worktree` marker file in the worktree
4. Clone each specified repo into the worktree directory
5. Patch `pyproject.toml` in the worktree:
   - Add packages under a `# --- workspace packages (editable) ---` comment in `[project.dependencies]`
   - Add `{ workspace = true }` entries in `[tool.uv.sources]`
   - Update `[tool.uv.workspace] members` to include cloned repo dirs
6. Handle `jupyter-chat` special case: workspace member path is `jupyter-chat/python/jupyterlab-chat`
7. Derive package names from each cloned repo's `pyproject.toml` `name` field
8. Run `uv sync` in the worktree
9. For each cloned repo with `package.json`: run `uv run jlpm && uv run jlpm build`
10. Enable server extensions (`jupyter server extension enable <pkg_name>`)
11. Enable lab extensions (`jupyter labextension develop . --overwrite`) for repos with `package.json`

### Task 6: Implement `subtree-add` recipe

`just subtree-add <repos...>` (only works inside a worktree):

1. Guard with `[ -f .is_worktree ]` check
2. Validate repo names against `repos.json`
3. Clone the new repos into the current worktree
4. Patch `pyproject.toml` to add the new workspace packages
5. Run `uv sync`
6. Build frontend + enable extensions for the new packages only

### Task 7: Add `start` and utility recipes

- `start` — `uv run jupyter lab --config=<path>/jupyter_server_config.py`
- `build` — rebuild frontend for all workspace packages
- `subtree-status` — list dev-installed packages (parse comment-marked section)
- `clean` — remove generated files

Guards:
- `subtree-add`, `subtree-status`, `build` require `.is_worktree`
- `subtree-create` requires `.is_worktree` does NOT exist

### Task 8: End-to-end test

1. `just subtree-create demo jupyter-ai-acp-client jupyter-ai-persona-manager`
2. Verify JupyterLab starts with both extensions
3. `cd worktrees/demo && just subtree-add jupyter-ai-router`
4. Verify all three packages are editable and extensions are enabled
