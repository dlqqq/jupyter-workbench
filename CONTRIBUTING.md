# Contributing

> **For AI agents:** This document explains how the workbench works internally and how to add or modify recipes. Read this before making changes to the justfile, helpers, or repos.json.

## Recipe Hierarchy

Recipes are organized into three groups based on where they can be run:

| Group | Runs from | `$PWD` is | Example |
|-------|-----------|-----------|---------|
| **workbench** | Workbench root | Workbench root | `worktree-add`, `worktree-remove`, `sync-recipes` |
| **worktree** | Worktree root | Worktree root | `add-dev`, `start`, `start-cmux`, `enable-all-extensions` |
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

### Adding a new repo

For a standard single-package repo (package name = repo name with `-` → `_`, pyproject.toml at root):

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

- `name`: The Python package name (used for `jupyter server extension enable <name>`)
- `parentDir`: Path from repo root to the directory containing `pyproject.toml`

## `.worktree_info`

A plain text file at the worktree root listing dev-installed repos, one per line. Managed by:
- `worktree-add`: writes initial list at creation
- `add-dev`: appends new repos

Used by `get_worktree_repos` to iterate dev repos without scanning the filesystem or parsing pyproject.toml.

## Files copied to worktrees

`worktree-add` copies these from the workbench root into each new worktree:
- `justfile`
- `scripts/` (helpers)
- `.env` (if present)

If you update the justfile or helpers, existing worktrees will have stale copies. This is intentional — worktrees are disposable. Create a new one to pick up changes, or manually copy the files.

## Adding a new recipe

1. Decide which group it belongs to (workbench, worktree, or repo)
2. Add the `[group('...')]` attribute
3. For repo recipes, add `[no-cd]`
4. Source helpers and call the appropriate `get_*` function with `$PWD`
5. Use `$WB_ROOT`, `$WT_ROOT`, `$REPO_ROOT` etc. for paths — never hardcode
