# Agents

## What is the Jupyter Workbench

The Jupyter Workbench is a Jupyter extension development orchestrator. It manages
parallel **workspaces** where you edit a few specific packages while everything
else installs from PyPI.

- The **workbench root** is the top-level repo. Source repos are pre-cloned once
  into `repos/` and shared across all workspaces.
- Each **workspace** is a git **worktree** of the workbench on branch
  `YYYYMMDD-<name>`. Because it's a worktree, you can edit workbench
  infrastructure (recipes, scripts, skills, docs) *and* dev-installed packages
  from the same place — up to **N+1 PRs** from one workspace (1 for the
  workbench + N for each dev-installed package).

Each workspace has three repo directories:

| Directory | Purpose |
|-----------|---------|
| `repos/` | Symlinks to shared source repos — read-only context. Browse here, never edit. |
| `dev/`   | Worktrees for editing. Dev-installed; push package PRs from here. |
| `tmp/`   | Worktrees for reading specific branches (`just dev checkout <repo> [branch]`). |

## Who you are

There are three roles. **Identify yours by your current working directory:**

| Role | Where | Job |
|------|-------|-----|
| **Root orchestrator** | Workbench root (CWD is *not* under `workspaces/`) | Manage the workbench; spawn workspaces for tasks and hand off. |
| **Workspace agent** | Under `workspaces/` | The agent scoped to one task inside a workspace. Drives it to completion, parallelizing via subagents/workflows when capable. |
| **Subagent** | Spawned by a workspace agent | A worker dispatched for a slice of work. Never created manually. |

## Root orchestrator

**If your CWD is the workbench root (not under `workspaces/`), you are the root
orchestrator.** You manage the workbench itself (the root checkout on `main`).
Your default is to **dispatch, not to do**: scaffold a workspace for the task
and hand off, because deep planning belongs inside the workspace where the agent
has full repo context.

To spawn a workspace agent for a task, follow `skills/spawn-workspace-agent/SKILL.md`.
In short: grill only enough for a go/no-go decision (use the `grill-me` skill),
pick the repos to dev-install, name the workspace, then `just ws create … --then …`
and write a thin `PLAN.md`. You scaffold; you do **not** plan the implementation.

Trivial one-off workbench tweaks that need no iteration (a doc fix, a recipe
one-liner) can be done here on `main` directly — but when in doubt, prefer a
workspace; it's cheap and keeps work isolated.

## Workspace agent

**If your CWD is under `workspaces/`, you are the workspace agent** — the
top-level agent for one task. Your job:

1. **Understand the task** — read `PLAN.md`; gather context and research the
   relevant repos. If anything is still unclear, grill the user (`grill-me`
   skill) before writing code.
2. **Plan** — expand `PLAN.md` into a concrete approach.
3. **Dispatch subagents** — drive work across repositories to completion, in
   parallel where it's independent (use subagents/workflows when capable). Point
   a subagent at the one skill it needs (e.g. `skills/open-pr/SKILL.md`) rather
   than loading all of them. Do this work yourself if subagents aren't available.

What you can produce from a workspace:

- **Edit dev-installed packages** — change `dev/<repo>` and open PRs to their
  upstream repos (commit/push from inside `dev/<repo>/`; run
  `just dev ensure-fork <repo>` first).
- **Edit workbench infrastructure** — change justfiles, scripts, skills, or docs
  and open a PR to the workbench (commit/push from the workspace root).

### Workflow

> Instructions in your prompt and `PLAN.md` always take precedence.

1. **Reproduce.** Prefer a failing test as your repro — `pytest` for backend
   (`.py`), a Galata E2E (or best available unit test) for frontend
   (`.ts`/`.tsx`/`.css`).
2. **Fix.** Backend editable installs pick up `.py` changes live. Frontend needs
   a rebuild before E2E — see `skills/rebuild-frontend/SKILL.md`.
3. **Cover.** Add test coverage at unit/integration level (E2E when supported).
4. **Verify.** From inside `dev/<repo>` (venv already active): `pytest`,
   `jlpm lint` (frontend), `mypy .` (if used).
5. **Notify.** `cmux notify --title "Done: <ws>" --body "..."` or
   `--title "Stuck: <ws>" --body "<blocker>"`.

### Rules

- Do NOT spawn new workspaces from within a workspace.
- Do NOT edit other workspaces or the workbench main checkout.
- Do NOT edit files in `repos/` — they're shared symlinks.
- Stay on your branch for workbench changes.
- Workspace artifacts (`.venv/`, `repos/`, `dev/`, `tmp/`, `pyproject.toml`,
  `.workspace_info.json`) are gitignored — only intentional workbench changes
  show in `git status`.

## Skills

Reusable procedures live in `./skills/` (symlinked to `.claude/skills/` and
`.kiro/skills/` for native discovery). Read a skill's `SKILL.md` when its
description matches your task.

| Skill | When to use |
|-------|-------------|
| `skills/grill-me` | Stress-test a plan by interviewing the user one question at a time. |
| `skills/land-workbench-pr` | Merge this workspace's approved workbench PR, then reset the worktree to a fresh branch off main. |
| `skills/open-pr` | Open a pull request from a repo in the workspace. |
| `skills/rebuild-frontend` | After frontend changes (`.ts`/`.tsx`/`.css`), before running E2E tests. |
| `skills/spawn-workspace-agent` | **Root orchestrator only** — scaffold a workspace and launch a workspace agent for a task. |

## Other references

- **Justfile recipes** — `just list-recipes` lists everything, grouped by
  `workbench` / `workspace` / `workspace-server` / `workspace-browser` /
  `workspace-jupyter-chat` / `workspace-notebook`.
- **Browser-eval scripts** — JS in `scripts/`, run via
  `just browser-eval <script> [args...]`.
- **[CONTRIBUTING.md](CONTRIBUTING.md)** — modifying recipes and workbench internals.
- **[README.md](README.md)** — quick start and architecture overview.
