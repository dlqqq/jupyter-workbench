# Contributing

How the workbench works internally. Read this before modifying justfiles or workbench infrastructure.

## Justfile Architecture

Recipes are split across 3 justfiles, each scoped to its directory level:

| File | Location | Groups |
|------|----------|--------|
| `justfile` | Workbench root | `[workbench]` |
| `worktree.just` → copied as `justfile` | Worktree root | `[worktree]`, `[worktree-server]` |
| `repo.just` → copied as `justfile` | Repo root | `[repo]` |

### Fallback

Lower-level justfiles use `set fallback` so recipes can call parent-level recipes:

```
repo justfile → worktree justfile → workbench justfile
```

For example, a repo recipe can call `just get-worktree-root` — `just` walks up until it finds the worktree's justfile which defines that recipe.

### Path resolution

Each justfile uses `{{ justfile_directory() }}` as its own root. To get a parent root:

```bash
# From a repo recipe, get the worktree root:
wt_root=$(just get-worktree-root)

# From a worktree recipe, get the workbench root:
wb_root=$(just get-workbench-root)
```

### Calling repo recipes from worktree recipes

Use a subshell to `cd` into the repo:

```bash
(cd "$wt_root/$repo" && just build)
```

## `repos.json`

Maps repo names to git URLs and optional package metadata. See `repos.schema.json` for the full schema.

Default conventions when `packages` is absent:
- `name` = repo key with `-` replaced by `_`
- `parentDir` = `.`

### Adding a new repo

For a standard single-package repo:

```json
"my-new-repo": { "url": "git@github.com:org/my-new-repo.git" }
```

For a repo with nested or differently-named packages:

```json
"my-repo": {
  "url": "git@github.com:org/my-repo.git",
  "packages": [
    { "name": "my_package_name", "parentDir": "path/to/package" }
  ]
}
```

## `.worktree_info.json`

JSON file at the worktree root tracking dev-installed repos and runtime state.

```json
{
  "dev-repos": ["jupyter-ai-router", "jupyter-chat"],
  "workspace_id": "",
  "server": {
    "surface_id": "surface:19",
    "url": "http://localhost:8888/",
    "token": "abc123...",
    "pid": 12345,
    "pgid": 12340
  },
  "browser": {
    "surface_id": "surface:22"
  }
}
```

- `dev-repos`: managed by `worktree-add` and `add-dev`
- `server`/`browser`: managed by `just server-start` and `just server-stop` (null when server is not running)

## Files copied to worktrees

`worktree-add` copies these from the workbench root into each new worktree:
- `worktree.just` → `justfile`
- `.kiro/skills/`
- `.env` (if present)
- `repo.just` → `<repo>/justfile` (for each dev repo, also adds to `.git/info/exclude`)

Worktrees use symlinks to the workbench root for justfiles and skills, so changes are reflected immediately — no sync step needed.

## Adding a new recipe

1. Decide which justfile it belongs to (`justfile`, `worktree.just`, or `repo.just`)
2. Add the appropriate `[group('...')]` attribute
3. Use `{{ justfile_directory() }}` for paths within the same level
4. Call `just get-worktree-root` or `just get-workbench-root` for parent paths
5. Use inline `jq` for reading/writing `.worktree_info.json`
