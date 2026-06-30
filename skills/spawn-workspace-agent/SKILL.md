---
name: spawn-workspace-agent
description: Spawn a workspace agent in a dedicated workspace to work on a task or GitHub issue. Determines which packages to dev-install, creates a workspace, opens a cmux workspace, and launches a workspace agent with a thin PLAN.md. ROOT ORCHESTRATORS ONLY — do not use from inside a workspace. Use when the user wants a task worked on in a fresh isolated workspace, says "spawn an agent for this", or provides a GitHub issue URL to delegate.
---

# Spawn Workspace Agent

Scaffold an isolated workspace and launch a workspace agent to work on a task.

**Root orchestrators only.** This is the root orchestrator's primary job:
triage just enough to scaffold, then hand off. Do NOT use this from inside a
workspace (workspace agents must not spawn new workspaces).

## When to Use

- User provides a GitHub issue URL or task and wants it worked on in isolation
- User says "spawn an agent for this", "delegate this", "work on this in a new session"

## Principle: scaffold, don't plan

The root orchestrator grills only enough to make a **go/no-go** decision and
**scaffold** the workspace. It does NOT plan the implementation — deep planning
happens inside the workspace, where the agent has full repo context. When in
doubt, gather context in the workspace, not at the root.

## Workflow

### Step 0: Grill (lightly) for go/no-go

Use the `grill-me` skill to surface ambiguity — but only enough to decide
whether to spawn and what to scaffold. If the task needs **a lot** of
clarification, don't try to resolve it all here. Recommend the user let the
workspace agent gather context first (it can grill them in-context with full
repo access). Better to gather context there than at the root.

### Step 1: Determine packages

Decide what the workspace needs:
- **Dev packages**: repos to clone and edit (check `repos.json` for valid names)
- **With packages**: PyPI packages needed in the env but not edited

Rules:
- For jupyter-ai subpackages, always include `--with jupyter-ai` (the main package)
- Propose the list to the user for confirmation

### Step 2: Rough summary of changes

Write a brief, high-level summary of what the task requires — enough to seed
PLAN.md. This is a rough sketch, not an implementation plan.

### Step 3: Name the workspace

Pattern: `<package-abbreviation>-<short-slug>`, e.g. `acp-defer-session-loading`,
`chat-fix-message-rendering`, `router-add-priority-routing`.

Abbreviations: `jupyter-ai`→`jai`, `jupyter-ai-acp-client`→`acp`,
`jupyter-ai-chat-commands`→`chatcmd`, `jupyter-ai-persona-manager`→`persona`,
`jupyter-ai-router`→`router`, `jupyter-ai-tools`→`tools`, `jupyter-chat`→`chat`,
`jupyter-server-documents`→`jsd`, `jupyter-server-mcp`→`mcp`,
`jupyterlab-commands-toolkit`→`cmdtk`.

### Step 4: Push back if too complex or vague

If the task is too complex or too vague to scaffold confidently, **redirect —
don't refuse.** Complexity is not a reason to avoid spawning; it's a reason not
to plan at the root. Spawn the workspace anyway, but seed PLAN.md so the
workspace agent does the research and planning itself.

### Step 5: Scaffold the workspace

Run from the workbench root. `ws create` only scaffolds — it makes the worktree,
venv, and an open cmux workspace, then returns. It does NOT provision or launch
an agent (that's Step 6–7).

```bash
just ws create <name>
```

The workspace directory exists synchronously when this returns, so you can write
files into it immediately.

### Step 6: Write setup.sh and a thin PLAN.md (both as files)

This is the heart of the handoff, and the reason the flow is split: **all
free-form text goes into files, never through a flag.** Passing a long prompt or
command string as a shell argument means it crosses 3–4 quoting layers (just →
cmux → terminal → CLI) and any em-dash, quote, `$`, or newline breaks it. Files
sidestep that entirely.

Write `setup.sh` to the workspace root — the provisioning chain that ends by
launching the agent:

```bash
#!/usr/bin/env bash
set -eo pipefail
just dev add <repos>
just dev setup [--with=<pkgs>]
just spawn-agent
```

- `<repos>` — comma-separated repos to dev-install (each optionally `<repo>#<pr>`)
- `--with=<pkgs>` — optional comma-separated PyPI packages (passed to `dev setup`)
- `dev add` creates the worktrees + editable members; `dev setup` syncs the venv
  and enables extensions; `spawn-agent` launches the CLI session with a FIXED
  prompt template (it derives the workspace name from the directory and tells the
  agent to read PLAN.md — there is no prompt argument to pass).

Write `PLAN.md` to the workspace root with just the handoff context:
- Task / issue link and title
- The rough summary from Step 2
- Which packages are dev-installed and why

Keep it thin — the workspace agent expands it after researching. Do NOT plan the
implementation here, and do NOT repeat general workflow info (build/test/notify
commands); the workspace agent reads that from AGENTS.md.

### Step 7: Provision and launch, then notify

Both files are on disk, so there is no PLAN.md race — run setup.sh in the
workspace's cmux terminal:

```bash
just ws setup <name>
```

This sources the venv and runs `setup.sh`. If provisioning fails (e.g. a version
conflict in `dev setup`), fix it and re-run `just ws setup <name>` — it's
idempotent up to the agent launch. Then notify the user:

```bash
cmux notify --title "Spawned: <workspace-name>" --body "<one-line task summary>"
```

## Notes

- The spawned agent is a separate CLI session — its own context and conversation
- The workspace is fully isolated — changes there don't affect other workspaces
- `setup.sh` and `PLAN.md` are gitignored workspace artifacts — they record how
  the workspace was provisioned and what it was asked to do
- TODO: Make the agent CLI configurable (support Codex, Claude Code, Kiro, etc.)
