---
name: spawn-agent
description: Spawn a new agent session in a dedicated workspace to work on a GitHub issue. Reads the issue, determines which packages to dev-install, creates a workspace, opens a cmux workspace, and launches a Kiro session with a plan. Use when the user says "spawn an agent for this issue", "work on this in parallel", or provides a GitHub issue URL they want delegated.
---

# Spawn Agent

Orchestrate a new parallel agent session to work on a GitHub issue in an isolated workspace.

## When to Use

- User provides a GitHub issue URL and wants it worked on in parallel
- User says "spawn an agent for this", "delegate this issue", "work on this in a new session"
- User wants to set up a development environment for a specific issue

## Workflow

### Step 1: Read the issue

Fetch the GitHub issue (title, body, labels, comments) to understand what needs to be done.

### Step 2: Determine packages

Based on the issue content, determine:
- **Dev packages**: repos that need to be cloned and edited (from `repos.json`)
- **With packages**: PyPI packages needed in the environment but not edited

Rules:
- For jupyter-ai subpackages, always include `--with jupyter-ai` (the main package)
- Check `repos.json` for available repo names
- Propose the list to the user for confirmation

### Step 3: Assess complexity and plan

Use intuition to assess whether the issue is simple or complex:
- **Simple** (bug fix, small feature, clear scope): Write a minimal PLAN.md with just the issue link, context, and repos. Spawn immediately.
- **Complex** (architectural change, multi-package coordination, unclear requirements): Engage the user in planning. Ask clarifying questions. Build out a detailed PLAN.md together before spawning.

The user can override: "just spawn it" or "let's plan this first."

### Step 4: Name the workspace

Use the pattern: `<package-abbreviation>-<short-slug>`

Examples:
- `acp-defer-session-loading`
- `chat-fix-message-rendering`
- `router-add-priority-routing`

Package abbreviations:
- `jupyter-ai` → `jai`
- `jupyter-ai-acp-client` → `acp`
- `jupyter-ai-chat-commands` → `chatcmd`
- `jupyter-ai-persona-manager` → `persona`
- `jupyter-ai-router` → `router`
- `jupyter-ai-tools` → `tools`
- `jupyter-chat` → `chat`
- `jupyter-server-documents` → `jsd`
- `jupyter-server-mcp` → `mcp`
- `jupyterlab-commands-toolkit` → `cmdtk`

### Step 5: Create the workspace

Run from the workbench root:
```bash
just workspace-add <name> --dev=<repos> [--with=<pkgs>]
```

### Step 6: Write PLAN.md

Write `PLAN.md` to the workspace root with:
- Issue link and title
- Issue body (or summary for long issues)
- Which packages are dev-installed and why
- Implementation guidance (level of detail depends on complexity)

Do NOT repeat general workflow info (build/restart/test/notify commands) — the worker agent will read that from AGENTS.md automatically.

### Step 7: Create cmux workspace and launch agent

```bash
# Create a new cmux workspace named after the workspace
cmux new-workspace --name "<workspace-name>"

# Get the workspace ref and surface ref
cmux list-pane-surfaces --workspace <workspace-ref> --json

# Build the prompt and send
PROMPT="You are a worker agent assigned to the <workspace-name> workspace under the Jupyter Workbench. First, read AGENTS.md if it is not already in your context. It describes the available recipes, skills, and general workflow for working in a workspace. Then read PLAN.md for your specific task. Follow the worker agent workflow described in AGENTS.md. Notify the user once you are complete or get stuck."

cmux send --workspace <workspace-ref> --surface <surface-ref> "cd <workspace-path> && kiro-cli chat --agent dlq -a '$PROMPT'\n"
```

## Notes

- The spawned agent is a separate Kiro CLI session — it has its own context and conversation
- The workspace is fully isolated — changes there don't affect other workspaces
- TODO: Make the agent CLI configurable (support Codex, Claude Code, etc.)
