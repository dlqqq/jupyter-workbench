# jupyter-workbench

A lightweight Jupyter extension development orchestrator. Create parallel workspaces with only the packages you're actively editing — everything else installs from PyPI.

## Quick Start

```bash
# Create a workspace with specific packages for development
just create-workspace my-feature --dev=jupyter-ai-acp-client,jupyter-ai-persona-manager

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
| `create-workspace <name> [--dev=<repos>] [--with=<pkgs>] [--spawn-agent] [--prompt=<text>]` | Create a new workspace (non-blocking) |
| `cleanup` | Delete all workspaces/worktrees not open in cmux |
| `create-worktree <name>` | Create a workbench worktree (git branch) |
| `remove-worktree <name> [--force]` | Remove a workbench worktree |
| `get-workbench-root` | Echo the workbench root path |

### Workspace recipes (`workspace.just` → `justfile`)

| Recipe | Description |
|--------|-------------|
| `start` | Start server and open browser |
| `add-dev <repos>` | Clone + editable install repos (comma-separated) |
| `add <pkgs>` | Add PyPI packages (comma-separated) |
| `sync` | Sync the venv (`uv sync`) |
| `spawn-agent` | Spawn an agent session from `.workspace_info.json` prompt |
| `stop-agent` | Stop the agent session |
| `close-workspace` | Stop agent + server, close cmux workspace |
| `workspace-status` | List dev-installed repos |
| `enable-all-extensions` | Enable extensions for all dev repos |
| `build-all` | Build all dev repos |

#### Server recipes (`[workspace-server]`)

| Recipe | Description |
|--------|-------------|
| `start-server` | Start JupyterLab in a new tab |
| `stop-server` | Stop the JupyterLab server |
| `restart-server` | Restart server and navigate browser to new URL (alias: `restart`) |
| `server-status` | Check if a server is running |

#### Browser recipes (`[workspace-browser]`)

| Recipe | Description |
|--------|-------------|
| `open-browser` | Open a browser to JupyterLab |
| `close-browser` | Close the browser |
| `refresh-browser` | Reload the browser |
| `get-browser-surface` | Print the browser surface ref |
| `browser-eval <script> [args...]` | Run a JS script in the browser |

#### Jupyter Chat recipes (`[workspace-jupyter-chat]`)

| Recipe | Description |
|--------|-------------|
| `open-chat [--mainarea]` | Open a new chat (side panel by default) |
| `send-chat-message <name> <message>` | Send a message to a chat by name |
| `read-chat-messages <name>` | Read all messages from a chat (JSON) |
| `list-chats` | List all chats visible in the Chat panel |

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
├── scripts/                    ← JS scripts for browser-eval
│   ├── open-chat-sidepanel.js
│   ├── open-chat-mainarea.js
│   ├── list-chats.js
│   └── read-chat-messages.js
├── tmp/                        ← scratch space (gitignored contents)
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
