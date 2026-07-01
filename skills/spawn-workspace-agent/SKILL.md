---
name: spawn-workspace-agent
description: Spawn a workspace agent in a dedicated workspace to work on a task or GitHub issue. Determines which packages to dev-install, creates a workspace, opens a cmux workspace, and launches a workspace agent with a PROMPT.md. ROOT ORCHESTRATORS ONLY — do not use from inside a workspace. Use when the user wants a task worked on in a fresh isolated workspace, says "spawn an agent for this", or provides a GitHub issue URL to delegate.
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
PROMPT.md. This is a rough sketch, not an implementation plan.

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
to plan at the root. Spawn the workspace anyway, but seed PROMPT.md so the
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

### Step 6: Write setup.sh and PROMPT.md (both as files)

This is the heart of the handoff, and the reason the flow is split: **all
free-form text goes into files, never through a flag.** Passing a long prompt or
command string as a shell argument means it crosses 3–4 quoting layers (just →
cmux → terminal → CLI) and any em-dash, quote, `$`, or newline breaks it. Files
sidestep that entirely.

Write `setup.sh` to the workspace root — the provisioning chain that ends by
launching the agent:

```bash
#!/usr/bin/env bash
set -uo pipefail   # NOT -e: provisioning failures must not block the launch

just dev add <repos>
just dev setup [--with=<pkgs>]

# Always reach the agent, even if provisioning failed above. The agent verifies
# its env on startup (AGENTS.md step 0) and can fix + re-run `just dev setup` —
# recovering in-context beats leaving a dead workspace for a human to notice.
just ws _launch-agent
```

- `<repos>` — comma-separated repos to dev-install (each optionally `<repo>#<pr>`)
- `--with=<pkgs>` — optional comma-separated PyPI packages (passed to `dev setup`)
- `dev add` creates the worktrees + editable members; `dev setup` syncs the venv
  and enables extensions; `ws _launch-agent` reads `PROMPT.md` and launches the
  agent CLI (from `workbench-config.json`'s `agent-cmd`) with the prompt as its
  final arg. It's the private launcher `ws spawn` relies on — always end
  `setup.sh` with it.
- **Do not use `set -e`** — if `dev setup` aborts, we still want the agent to
  launch so it can diagnose the failure from its scrollback and recover.

Write `PROMPT.md` to the workspace root — this **is** the agent's prompt
(`ws _launch-agent` passes its contents verbatim to the agent CLI). Open with the
worker framing, then the task:

```markdown
You are the workspace agent for the <name> workspace under the Jupyter Workbench.
Read AGENTS.md first if it isn't already in your context — it describes the
recipes, skills, and workflow. Gather context and research first; if anything is
unclear, grill the user with the grill-me skill before writing code. Open a PR
for each affected repo when done, and notify the user when complete or stuck.

## Task

<task / issue link + title, the rough summary from Step 2, and which packages are
dev-installed and why>
```

Keep the task section thin — the workspace agent expands it after researching. Do
NOT plan the implementation here, and do NOT repeat general workflow info
(build/test/notify commands); the agent reads that from AGENTS.md.

### Step 7: Provision and launch, then notify

Both files are on disk, so there is no race — `ws spawn` requires `setup.sh` and
`PROMPT.md` and errors immediately if either is missing, then runs `setup.sh` in
the workspace's cmux terminal:

```bash
just ws spawn <name>
```

This sources the venv and runs `setup.sh`, which provisions and ends by launching
the agent. If provisioning fails (e.g. a version conflict in `dev setup`), fix it
and re-run `just ws spawn <name>` — it's idempotent up to the agent launch. Then
notify the user:

```bash
cmux notify --title "Spawned: <workspace-name>" --body "<one-line task summary>"
```

## Notes

- The spawned agent is a separate CLI session — its own context and conversation
- The workspace is fully isolated — changes there don't affect other workspaces
- `setup.sh` and `PROMPT.md` are gitignored workspace artifacts — they record how
  the workspace was provisioned and what it was asked to do
- `ws spawn` is the orchestrator's provision+launch verb; `ws _launch-agent` is
  the private launcher `setup.sh` ends with. Neither is meant for a human to run
  by hand outside this flow.
- TODO: Make the agent CLI configurable (support Codex, Claude Code, Kiro, etc.)
