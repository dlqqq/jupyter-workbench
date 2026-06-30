# Contributing

How the workbench works internally. Read this before modifying recipes or workbench infrastructure.

## Modular justfiles

The root `justfile` composes submodules via `mod`:

| Module | File | Purpose |
|--------|------|---------|
| `repos` | `repos/justfile` | Pre-clone/fetch source repos (`just repos clone`) |
| `dev` | `dev/justfile` | Per-workspace repo management (`add`, `setup`, `remove`, `checkout`, `ensure-fork`, `enable-extensions`) |
| `ws` | `workspaces/justfile` | Workspace lifecycle (`create`, `rm`, `cleanup`) |
| `server` | `server.just` | **Deprecated** — cmux/macOS JupyterLab server control |
| `browser` | `browser.just` | **Deprecated** — cmux/macOS browser control |

`repos/`, `dev/`, and `workspaces/` have their directory *contents* gitignored but
their `justfile` tracked (see `.gitignore`). Since each workspace is a worktree of
the same repo, every module is available from inside a workspace too.

> The `server` and `browser` modules are being replaced by JupyterLab's Galata
> (Playwright) E2E framework so the workbench can run on Linux/CI. Don't add new
> automation that depends on them.

### Path resolution

Each module defines `root := justfile_directory()` (which always resolves to the
root justfile's directory — i.e. the workbench or workspace root) and marks recipes
`[no-cd]` so they run from the invocation directory. In bash blocks, assign
`root="{{ root }}"` and use `$root`.

To find the shared clones at the workbench root from inside a workspace worktree:

```bash
wb_repos="$(git rev-parse --path-format=absolute --git-common-dir | sed 's|/\.git$||')/repos"
```

### Venv activation

`just spawn-agent <prompt>` sources `.venv/bin/activate` before launching the agent,
and `ws create` activates the venv in the new cmux workspace's terminal. So agents
run `pytest`, `jlpm`, `mypy`, etc. directly.

## Workspaces (= git worktrees)

`just ws create <name>` runs:

```bash
git worktree add -b "YYYYMMDD-<name>" "workspaces/<name>"
```

then generates `pyproject.toml` (project name = workspace name), creates an empty
venv (`uv venv`), and symlinks every pre-cloned repo into the workspace's `repos/`.
Agents can edit both dev-installed packages AND workbench infrastructure from one
workspace, producing up to N+1 PRs.

## Repo layout (repos/ / dev/ / tmp/)

- **Workbench `repos/`** — pre-cloned source repos shared across workspaces. Populated by `just repos clone`. `repos clone` also sets `remote.origin.gh-resolved=base` so `gh pr checkout` resolves non-interactively.
- **Workspace `repos/`** — symlinks to the workbench `repos/<name>`; read-only context.
- **Workspace `dev/`** — worktrees created from the source repos, each on its own branch `YYYYMMDD-<ws>/<repo>`, added as editable members. `just dev add` creates them (no sync); `just dev setup` runs `uv sync` + enables extensions. PR checkouts land on the workspace-scoped branch (`gh pr checkout --branch`).
- **Workspace `tmp/`** — worktrees for reading specific branches (`just dev checkout <repo> [branch]`). Not dev-installed.

## Clean git state

Workspace artifacts are gitignored: `.workspace_info.json`, `.venv/`, `uv.lock`,
`screenshots/`, `.env`, `pyproject.toml`, `repos/`, `dev/`, `tmp/`.

## `repos.json`

Maps repo names to git URLs and optional package metadata. See `repos.schema.json`.

Default conventions when `packages` is absent:
- `name` = repo key with `-` replaced by `_`
- `parentDir` = `.`

## `.workspace_info.json`

Runtime state only (which repos are dev-installed is determined by scanning `./dev`):

```json
{
  "server": null,
  "browser": null,
  "agent": { "pgid": 12350 }
}
```

`agent` is managed by `spawn-agent`/`stop-agent`; `server`/`browser` by the
(deprecated) server/browser modules.

## Tests

bats tests live in `workbench-tests/` (`ws.bash`, `dev.bash`, `repos.bash`, shared
`helpers.bash`). Run with `just workbench-tests run-all` or `just workbench-tests run <file>`.
Tests are hermetic (no network): `dev` tests use a local fake source repo, and they
create throwaway workspaces, cleaning up worktrees/branches/trash in teardown. Add
coverage when you change recipes, and commit before running — workspace worktrees are
created from `HEAD`, so uncommitted recipe changes won't be seen by tests that run
`just` from inside a worktree.

## Adding a new recipe

1. Put it in the right module file (`repos/justfile`, `dev/justfile`, `workspaces/justfile`, or the root `justfile`).
2. Mark it `[no-cd]` and assign `root="{{ root }}"` at the top of bash blocks.
3. Use inline `jq` for `.workspace_info.json`.
4. Add a bats test under `workbench-tests/`.
