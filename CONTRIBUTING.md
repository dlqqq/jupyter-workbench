# Contributing

How the workbench works internally. Read this before modifying the justfile, helpers, or workbench infrastructure.

## Recipe Hierarchy

Recipes are organized into three groups based on where they can be run:

| Group | Runs from | `$PWD` is | Example |
|-------|-----------|-----------|---------|
| **workbench** | Workbench root | Workbench root | `worktree-add`, `worktree-remove`, `sync-workbench` |
| **worktree** | Worktree root | Worktree root | `add-dev`, `server-start`, `server-stop`, `server-restart`, `enable-all-extensions` |
| **repo** | Inside a repo | Repo dir (via `[no-cd]`) | `build`, `enable-repo-extensions` |

## Working Directory Conventions

- **Workbench and worktree recipes** do NOT use `[no-cd]`. `$PWD` = `justfile_directory()` = the directory containing the justfile (workbench root or worktree root).
- **Repo recipes** use `[no-cd]`. `$PWD` = where the user (or parent script) invoked `just`. This allows them to be called from inside a repo directory.

### Calling repo recipes from worktree recipes

Use a subshell to `cd` into the repo before invoking `just`:

```bash
(cd "$WT_ROOT/$repo" && just enable-repo-extensions)
```

The subshell ensures:
1. `just` is invoked from the repo dir
2. With `[no-cd]`, the recipe's `$PWD` = repo dir
3. The parent loop's working directory is unaffected

Do NOT use `--working-directory` — it is ignored by `[no-cd]` recipes.

## `scripts/helpers.sh`

All recipes source this file for path resolution. Functions set global variables rather than printing to stdout (no subshell overhead).

```bash
source "{{ helpers }}"
get_worktree_root "$PWD" || exit 1
# Now $WT_ROOT is set
```

### Available functions

| Function | Sets | Requires |
|----------|------|----------|
| `get_workbench_root <dir>` | `WB_ROOT` | — |
| `get_worktree_root <dir>` | `WT_ROOT` | — |
| `get_worktree_repo <dir>` | `REPO_ROOT`, `REPO_NAME`, also sets `WT_ROOT` | — |
| `get_worktree_repos` | `WT_REPOS` (array) | `WT_ROOT` |
| `get_repo_pkg_names` | `PKG_NAMES` (array) | `WB_ROOT`, `REPO_NAME` |
| `get_repo_pkg_parents` | `PKG_PARENT_DIRS` (array) | `WB_ROOT`, `REPO_NAME` |

All path-walking functions accept a starting directory argument and walk up until they find the relevant marker.

## `repos.json`

Maps repo names to git URLs and optional package metadata. See `repos.schema.json` for the full schema.

Default conventions when `packages` is absent:
- `name` = repo key with `-` replaced by `_`
- `parentDir` = `.`

### Adding a new repo

For a standard single-package repo (package name = repo key with `-` → `_`, pyproject.toml at root):

```json
"my-new-repo": { "url": "git@github.com:org/my-new-repo.git" }
```

For a repo where the Python package is nested or has a different name:

```json
"my-repo": {
  "url": "git@github.com:org/my-repo.git",
  "packages": [
    { "name": "my_package_name", "parentDir": "path/to/package" }
  ]
}
```

- `name`: Python package name (used for `jupyter server extension enable <name>`)
- `parentDir`: Path from repo root to the directory containing `pyproject.toml`

## `.worktree_info.json`

JSON file at the worktree root tracking dev-installed repos and runtime state.

```json
{
  "dev-repos": ["jupyter-ai-router", "jupyter-chat"],
  "workspace_id": "",
  "server": {
    "surface_id": "surface:19",
    "url": "http://localhost:8888/",
    "token": "abc123..."
  },
  "browser": {
    "surface_id": "surface:22"
  }
}
```

- `dev-repos`: managed by `worktree-add` and `add-dev`
- `server`/`browser`: managed by `just server-start` and `just server-restart` (null when server is not running)

## Files copied to worktrees

`worktree-add` copies these from the workbench root into each new worktree:
- `justfile`
- `scripts/` (helpers)
- `.env` (if present)

If you update the justfile, helpers, or skills, existing worktrees will have stale copies. Run `just sync-workbench` to update them, or create a new worktree.

## Adding a new recipe

1. Decide which group it belongs to (workbench, worktree, or repo)
2. Add the `[group('...')]` attribute
3. For repo recipes, add `[no-cd]`
4. Source helpers and call the appropriate `get_*` function with `$PWD`
5. Use `$WB_ROOT`, `$WT_ROOT`, `$REPO_ROOT` etc. for paths — never hardcode
