# Agents

<!-- This AGENTS.md is for orchestrator agents and worktree worker agents.
     Workspace worker agents use the AGENTS.md in workspaces/templates/AGENTS.md instead. -->

jupyter-workbench is a Jupyter extension development orchestrator. It manages parallel workspaces where developers edit specific packages while the rest install from PyPI. It also supports workbench worktrees for modifying the workbench itself in parallel.

## Orchestrator (main workbench root)

You manage the workbench. Your job is to create workspaces for new tasks and spawn agent sessions to work on them. Use the `spawn-agent` skill when the user gives you a GitHub issue to delegate. One workspace per task.

### Recipes

| Recipe | Description |
|--------|-------------|
| `add-workspace <name> [--dev=<repos>] [--with=<pkgs>]` | Create a new workspace |
| `remove-workspaces <names> [--all]` | Remove workspaces |
| `add-worktree <name>` | Create a workbench worktree |
| `remove-worktree <name> [--force]` | Remove a workbench worktree |

## Worktree worker (inside `worktrees/<name>/`)

You are editing workbench infrastructure (recipes, skills, docs, templates). Your worktree is a git branch of `jupyter-workbench` itself.

### Workflow

1. **Make your changes** — edit justfiles, skills, docs, templates, etc.
2. **Test** — create a workspace to verify recipe changes work:
   ```bash
   just add-workspace test --dev=<repo>
   cd workspaces/test
   # test your changes
   just remove-workspaces test
   ```
3. **Commit and push** your branch.
4. **Open a PR** — `gh pr create`
5. **Notify the user:**
   - Done: `cmux notify --title "Done: <worktree>" --body "<brief summary>"`
   - Stuck: `cmux notify --title "Stuck: <worktree>" --body "<what's blocking>"`

### Rules

- Do NOT modify the main workbench or other worktrees
- Stay on your branch
- Clean up test workspaces before opening a PR

## Justfile Architecture

Recipes are split across 3 justfiles using `set fallback`:

| File | Location | Groups |
|------|----------|--------|
| `justfile` | Workbench root | `[workbench]` |
| `workspace.just` → `justfile` | Workspace root | `[workspace]`, `[workspace-server]` |
| `repo.just` → `justfile` | Repo root | `[repo]` |

Run `just list-recipes` to see all available recipes at your current level.

## Modifying recipes or workbench internals

See [CONTRIBUTING.md](CONTRIBUTING.md).
