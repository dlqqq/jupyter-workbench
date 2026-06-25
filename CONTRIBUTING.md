# Contributing

How the workbench works internally. Read this before modifying recipes or workbench infrastructure.

## Single Justfile

All recipes live in one `justfile` at the repo root. Groups separate concerns:

- `[workbench]` — workspace lifecycle (create, cleanup, clone-all)
- `[workspace]` — operations inside a workspace (dev, setup, agent, etc.)
- `[workspace-server]` / `[workspace-browser]` — server and browser management
- `[workspace-jupyter-chat]` / `[workspace-notebook]` — domain-specific helpers

Since each workspace is a worktree of the same repo, the justfile is always available.

### Path resolution

A `root` variable is defined at the top:

```just
root := justfile_directory()
```

All recipes use `$root` in bash (assigned as `root="{{ root }}"`).

### Venv activation

`spawn-agent` sources `.venv/bin/activate` before launching the agent. Agents can run `pytest`, `jlpm`, `mypy`, etc. directly.

## Workspaces (= git worktrees)

Each workspace is a git worktree. `create-workspace` runs:

```bash
git worktree add -b "YYYYMMDD-<name>" "workspaces/<name>"
```

Agents can edit both dev-installed packages AND workbench infrastructure from the same workspace, producing up to N+1 PRs.

## Repo layout (repos/ / dev/ / tmp/)

### Workbench root `repos/`

Pre-cloned source repos shared across all workspaces. Populated by `just clone-all`. Never edited directly.

### Workspace `repos/`

Symlinks to workbench `repos/<name>`. Gives agents read-only access to all source code for context.

### Workspace `dev/`

Git worktrees created from the source repos. Each worktree gets its own branch (`YYYYMMDD-<ws-name>/<repo-name>`). These are editable and dev-installed via `uv add --editable`.

### Workspace `tmp/`

Git worktrees for reading specific branches. Created by `just checkout-repo <name> <branch>`. Not dev-installed.

## Clean git state

Workspace artifacts are gitignored via `.gitignore`:

- `.workspace_info.json`, `.venv/`, `uv.lock`, `screenshots/`, `.env`
- `repos/`, `dev/`, `tmp/`

## `repos.json`

Maps repo names to git URLs and optional package metadata. See `repos.schema.json` for the full schema.

Default conventions when `packages` is absent:
- `name` = repo key with `-` replaced by `_`
- `parentDir` = `.`

## `.workspace_info.json`

Tracks dev-installed repos and runtime state:

```json
{
  "dev-repos": { "jupyter-ai-router": {}, "jupyter-chat": { "pr-number": 42 } },
  "prompt": "",
  "agent": { "pgid": 12350 },
  "server": { "surface_id": "...", "url": "...", "token": "...", "pid": 12345, "pgid": 12340 },
  "browser": { "surface_id": "..." }
}
```

## Browser Eval Scripts (`scripts/`)

JS function expressions for `just browser-eval`. Return `'ERROR: ...'` to signal failure.

## Adding a new recipe

1. Add the appropriate `[group('...')]` attribute
2. Use `root="{{ root }}"` at the top of bash blocks
3. Use inline `jq` for `.workspace_info.json`
