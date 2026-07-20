---
name: handoff-project-board
description: Spawn worker agents in parallel to work on all open issues on a GitHub project board. Groups related issues into a single agent, moves each issue to "In Progress" on spawn, and instructs agents to move issues to "Needs Review" once their draft PR passes CI. ROOT ORCHESTRATORS ONLY. Use when the user gives a project-board URL and wants every open issue worked on, or says "/handoff-project-board".
---

# Handoff Project Board

Read every open issue on a GitHub project board, plan a set of worker agents
(grouping issues that touch the same area into one agent), confirm the plan with
the user, then spawn one workspace agent per group — moving issues across the
board as work starts and finishes.

**Root orchestrators only.** This is a batch driver over
`skills/spawn-workspace-agent` — read that skill first; it owns the mechanics of
scaffolding and launching a single workspace. This skill adds board reading,
issue grouping, and board-state transitions on top.

## When to use

- User provides a project-board URL (e.g.
  `https://github.com/orgs/jupyterlab/projects/15/views/1`) and wants all open
  issues worked on.
- User invokes `/handoff-project-board`.

## Principle: one agent per area, not per issue

Two issues that touch the same code (e.g. two E2E-test additions in the same
package, or a doc pass plus a comment-to-docstring migration in one repo) should
be handled by **one** worker agent — spawning two would create conflicting
worktrees and duplicate context. Group issues by the repo + area they touch; each
group becomes one worker agent that opens one PR per affected repo and closes out
all its issues.

## Workflow

### Step 0: Clone/refresh repos

Same as `spawn-workspace-agent` Step 0 — run once up front:

```bash
just repos clone
```

### Step 1: Read the board

Resolve the project's owner and number from the URL
(`.../orgs/<owner>/projects/<number>/...`; for user projects it's
`.../users/<owner>/...`), then pull the field metadata and items. You need the
**Status field ID** and the **option IDs** for "In Progress" and "Needs Review"
(names vary per board — match case-insensitively, and if a board uses different
names ask the user which options mean "work started" and "ready for review").

```bash
OWNER=jupyterlab; NUM=15
# Status field + option IDs (save the ids for In Progress / Needs Review)
gh project field-list "$NUM" --owner "$OWNER" --format json \
  | jq '.fields[] | select(.name=="Status") | {fieldId:.id, options:.options}'
# All items with their content, repo, labels, status, and project item id
gh project item-list "$NUM" --owner "$OWNER" --format json \
  | jq '.items[] | {id, status, title, url:.content.url, repo:.content.repository, number:.content.number, labels}'
# Project node id (needed for item-edit)
gh project view "$NUM" --owner "$OWNER" --format json | jq '{projectId:.id}'
```

**Which items count as "open."** By default, target items whose status is a
backlog/active column (i.e. *not* already In Progress, Needs Review, In Review,
or Done) and whose underlying issue is open. Skip items that are already In
Progress or beyond — someone's on them. Confirm the target set with the user in
Step 4 rather than guessing; if the board mixes 2.x/3.x backlogs, ask which the
user wants worked.

### Step 2: Fetch each issue's body

The board listing includes issue bodies, but read the full issue (and skim linked
issues/PRs it references) for anything that changes grouping or package choice:

```bash
gh issue view <url> --json title,body,labels,comments
```

### Step 3: Plan the worker agents

Group the open issues into worker agents. For each group decide:

- **Issues** — which board issues this agent owns (one or more).
- **Repos to dev-install** — the repos the agent will edit (from `repos.json`).
  Follow `spawn-workspace-agent` Step 2 rules (e.g. jupyter-ai subpackages always
  add `--with jupyter-ai`).
- **`--with` packages** — PyPI deps needed in the env but not edited.
- **Workspace name** — `<pkg-abbrev>-<short-slug>` per `spawn-workspace-agent`
  Step 4. When one agent spans multiple issues, name it for the shared theme
  (e.g. `persona-e2e-tests`).

Grouping heuristics:

- Same repo **and** same area/feature → one agent (e.g. several E2E tests for one
  package).
- Same repo but clearly independent changes → separate agents *only* if they
  won't collide in the same files; when unsure, prefer one agent to avoid
  worktree conflicts.
- A bug whose fix spans repos (server + downstream) → one agent that dev-installs
  both repos.

Grill the user (`grill-me` skill) on anything unclear — ambiguous grouping,
which backlog to target, a package choice you can't infer, or an issue that looks
too vague to hand off. One question at a time.

### Step 4: Confirm the plan with the user

**Do not spawn anything yet.** Present the full plan as a table and get explicit
confirmation. Show, for every agent:

- Workspace name
- Issue(s) it will work on (number + title)
- Repos dev-installed (edited) and `--with` packages (env only)

Example format:

```
Agent: persona-e2e-tests
  Issues:  #62 Verify settings cleared when switching personas
           #77 Add E2E coverage for loading personas placeholder
  Dev:     jupyter-ai-persona-manager
  With:    jupyter-ai

Agent: jsd-awareness-on-connect
  Issues:  #279 Awareness state not sent to client on connect
  Dev:     jupyter-server-documents
  With:    (none)
```

Ask the user to confirm, adjust groupings, or drop issues. Wait for approval.

### Step 5: For each approved agent — move issues, scaffold, spawn

Once approved, process each agent. **Move its issues to "In Progress" as you spawn
it** (so the board reflects that work has started):

```bash
# For each issue this agent owns:
gh project item-edit --id <ITEM_ID> --project-id <PROJECT_ID> \
  --field-id <STATUS_FIELD_ID> --single-select-option-id <IN_PROGRESS_OPTION_ID>
```

Then scaffold and launch exactly as in `skills/spawn-workspace-agent` Steps 6–8:

1. `just ws create <name>`
2. Write `setup.sh` (dev-install repos + `dev setup [--with=...]` + `ws
   _launch-agent`) and `PROMPT.md` (see template below).
3. `just ws spawn <name>`

Spawn agents back-to-back — they run independently in their own cmux workspaces.

### Step 6: PROMPT.md template — the standard worker prompt

Each worker agent gets the standard prompt: **write a failing test first (for
bugs), iterate with subagents as needed, add/confirm tests, open a draft PR** —
plus the board-transition instruction. Keep the task section thin; the agent
researches and plans in-context.

```markdown
You are the workspace agent for the <name> workspace under the Jupyter Workbench.
Read AGENTS.md first if it isn't already in your context — it describes the
recipes, skills, and workflow. Gather context and research first; if anything is
unclear, grill the user (grill-me skill) before writing code. Parallelize with
subagents/workflows where work is independent.

## Task

You own these GitHub issue(s) from the "<board title>" project board:

- <issue URL> — <title>
- <issue URL> — <title>   (only if this agent owns more than one)

<one-line why these are grouped, e.g. "both add E2E coverage to the persona
picker in jupyter-ai-persona-manager">

Dev-installed: <repos and why>. Also in the env (not edited): <--with packages>.

## How to work each issue

1. Reproduce first. For a bug, add a FAILING test that captures it before
   changing any code (pytest for backend; a Galata E2E — or the best available
   test — for frontend). For a feature/enhancement, sketch the test that will
   verify it.
2. Implement the fix or feature, iterating with subagents where useful.
3. Cover it: ensure the bug's test now passes, or add tests that verify the new
   feature. Then run the repo's checks (pytest, jlpm lint, mypy if used) from
   inside dev/<repo>.
4. Open ONE draft PR per affected repo via skills/open-pr. Reference the issue(s)
   it closes (e.g. "Fixes #62"). The skill labels the PR for the changelog and
   watches CI to green.

## When your PR is green — move the board

After open-pr confirms CI is green, move each issue you own to "Needs Review" on
the project board, then notify:

    gh project item-edit --id <ITEM_ID_FOR_THIS_ISSUE> \
      --project-id <PROJECT_ID> --field-id <STATUS_FIELD_ID> \
      --single-select-option-id <NEEDS_REVIEW_OPTION_ID>

    cmux notify --title "Done: <name>" --body "<one-line summary + PR link(s)>"

The exact ids for your issue(s) are:
<paste the ITEM_ID for each issue this agent owns, plus PROJECT_ID,
STATUS_FIELD_ID, and NEEDS_REVIEW_OPTION_ID — resolved in Step 1>

If you get stuck (env broken, CI red you can't fix), leave the issue In Progress
and notify early: cmux notify --title "Stuck: <name>" --body "<blocker>".
```

**Important:** resolve the real `ITEM_ID` (per issue), `PROJECT_ID`,
`STATUS_FIELD_ID`, and `NEEDS_REVIEW_OPTION_ID` in Step 1 and paste the literal
values into each PROMPT.md. The worker agent can't run `gh project` discovery
reliably without them, and passing exact ids avoids it editing the wrong item.

### Step 7: Notify the user

After all agents are spawned:

```bash
cmux notify --title "Handed off: <board title>" \
  --body "Spawned <N> agents across <M> issues. Issues moved to In Progress."
```

## Notes

- **Board writes need project scope.** `gh project item-edit` requires the token
  to have the `project` scope. If it 403s, tell the user to run
  `gh auth refresh -s project` — don't silently skip the move.
- Moving to "In Progress" happens **here** (as each agent spawns); moving to
  "Needs Review" happens **inside the worker** (after CI is green). Never move an
  issue to Needs Review from here — the PR might not be green yet.
- Every worker opens PRs as **drafts** only (see `skills/open-pr`). Marking
  ready-for-review / merging stays with the user.
- This skill scaffolds and hands off. It does NOT plan any issue's implementation
  — that happens inside each workspace, per the Jupyter Workbench principle.
- One agent per area, not per issue: re-read Step 3's grouping heuristics before
  finalizing — over-splitting causes worktree collisions and wasted context.
