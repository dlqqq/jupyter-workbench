---
name: open-pr
description: Open a draft pull request from a repo in a workspace, label it for the changelog, and watch CI to green. Use when opening a PR for your changes (agents may do this without asking; PRs open in draft).
---

# Open a Pull Request

Push your changes to a fork and open a PR against the upstream repo.

**Agents may open PRs without asking** — but **always open them in draft status**.
A draft PR is the request for review; you do not need explicit permission to
create one. You still do NOT mark a PR ready-for-review or merge it without the
user.

## Prerequisites

- Your changes are in the `dev/<repo>` worktree (already on its own branch)
- `gh` CLI authenticated

## Steps

### 1. Ensure fork exists

From the workspace root:

```bash
just dev ensure-fork <repo-name>
```

This creates a GitHub fork (if needed) and sets up the `fork` remote + `gh repo set-default` for `dev/<repo-name>`.

### 2. Commit your changes

Your `dev/<repo>` worktree is **already on its own branch** (created by `dev add`),
so there's no need to create one. Just commit from inside the worktree:

```bash
(cd dev/<repo> && git add -A && git commit -m "<concise description of changes>")
```

> Every command below operates on a specific repo. If your working directory is the
> workspace root, run repo-scoped commands inside a subshell — `(cd dev/<repo> && …)`
> — or otherwise ensure you're in `dev/<repo>`. Running `git`/`gh` from the workspace
> root targets the wrong repo.

### 4. Write the PR body

Do **not** create a `PR.md` file. Writing a document makes the body balloon into a
padded, headings-everywhere essay. A PR body is a short note to a busy reviewer, not
a report. Write it directly into the `gh pr create` command (step 5).

**You are writing for maintainers.** They already understand the codebase and the
high-level concepts. Your job is to tell them two things well: **why** this change
is needed (what was wrong for users or devs), and **what** you're proposing. Get
those right and the PR gets accepted; everything else is noise.

Use these sections, in this order. Keep paragraphs short — a few sentences each.
Length scales with the change: a one-liner may collapse Motivation into a single
issue link and skip Technical details entirely.

```markdown
## Motivation

Work backwards from the problem. What context should a maintainer have? What
frustrated users or developers, or what new capability is needed — and *why*? This
is the most important section; it's what earns the review. If an issue already
covers all of it, DELETE this section and replace it with a link: `Fixes #123`.

## Summary

A few sentences on what the change does and its impact on users and developers.
Describe the new behavior in plain language, not the code that implements it.

## Technical details

Only what isn't already obvious from the Summary or the diff — design decisions,
tangential fixes, cross-repo dependencies. Bullets are fine.
```

Add a short `## Testing` section if how you verified it isn't obvious (one line:
what you tested, not a pass count).

**Style rules — these are where agents usually go wrong:**
- **Write to maintainers, not to a grader.** No "X/Y tests passing", no line
  numbers, no exhaustive change logs. That detail is noise; the diff has it.
- **Don't enumerate method/symbol names** when the prose already conveys the
  change. "This mostly reverts #54" beats a bulleted list of every removed function.
- **Links are summaries, not dumps.** Link an issue/PR and say in a few words what
  it is; a reader who wants specifics clicks through. Don't inline version numbers,
  merge status, release tags.
- **Short paragraphs.** A few sentences each. Split anything longer.
- **Newlines:** GitHub renders every single `\n` as a hard line break (it does not
  follow the `\n\n` convention). Blank line between paragraphs; never a bare single
  newline mid-paragraph.
- **Bold almost nothing.** Reserve it for one genuine "don't miss this" point (a UI
  contract, a breaking change). Bolding every noun is the #1 tell of an AI-written
  PR — avoid it.
- Calm and direct. No "dramatically improves", no hype. If it reads breathless, cut.

**Canonical example** — a real, maintainer-approved body
([jupyter-ai-persona-manager#59](https://github.com/jupyter-ai-contrib/jupyter-ai-persona-manager/pull/59)).
Study the voice: rich *why*, plain *what*, one purposeful bold, no symbol dumps, no
test counts, links summarized.

```markdown
## Motivation

Previously, messages were routed to AI personas based on `@`-mentions inside of the message body. When an AI persona was `@`-mentioned, it would always respond. The last-mentioned persona would also automatically respond but only if a single human user was connected to the chat. Users found it annoying to constantly `@`-mention personas to get them to reply consistently, and frequently asked why AI personas stopped auto-responding in multi-user RTC environments.

There were also a couple of other problems:

- When multiple AI personas were `@`-mentioned, they would respond in parallel. This is almost never a user's intention, and people found this behavior confusing. The multi-persona invocation story was never finished, and this is a quirk of Jupyter AI v3.0.

- When an AI persona referred to another AI persona by name (e.g. "I don't know the answer to that, but perhaps `@Kiro` knows"), it could trigger an infinite loop. It was too easy to accidentally mention other AI personas.

## Summary

Routing is now as simple as it should be: each chat message carries the ID of the persona it's directed to in its own metadata (`metadata["to_persona"]`). By making this field per-message, different users can have different AI personas configured in the same chat, allowing for seamless collaboration that doesn't rely on guessing internal state like the last active/mentioned/default persona. This mostly reverts #54 as a result.

**The new UI contract:** the persona in the persona picker UI that a user sees is **always** the one that responds to their messages, regardless of whether they have other peers connected or not.

## Technical details

- The default persona configurable trait now just sets `PageConfig` data that tells the UI to have a persona pre-selected.

- Multi-persona invocation has been disabled as there is no clear story for this. Even for multi-agent orchestration features we are planning, this seems unnecessary as it generally always makes sense to work with a single orchestrator/planner before starting a workflow.

- Personas can now `@`-mention each other. Infinite loops are avoided by design as personas must explicitly define and configure support for mentioning other AI personas.

- This requires an upstream change in Jupyter Chat (jupyterlab/jupyter-chat#465) and a downstream change in the persona picker UI living in `jupyter-ai-acp-client` (jupyter-ai-contrib/jupyter-ai-acp-client#135), which will eventually be moved here.

## Testing

- Replaced existing unit tests with ones that assert the new message-based routing introduced here.
```

**Contrast — what an unedited agent draft of that same PR looked like, and why it's worse:**
- It opened straight at `## Summary` with **no Motivation** — the single most
  important section for a reviewer was missing.
- A `## Changes` section listed every touched symbol (`active_persona`,
  `set_active_persona`, `_init_active_persona`, `ACTIVE_PERSONA_METADATA_KEY`, …) —
  noise the diff already shows. The good version compresses all of it to "mostly
  reverts #54".
- Test detail named the exact test classes added/removed instead of one line.
- Nearly every noun was bolded (`**Removed**`, `**Renamed**`, `**PageConfig**`),
  and links carried inline release/merge trivia (`released in @jupyter/chat 0.23.0a3`).

The rewrite is shorter, yet a maintainer understands it faster — because it leads
with *why* and describes behavior, not code.

**Screenshots:** if the change is visual, mention that screenshots are attached.
Local `screenshots/…` paths won't render on GitHub, so note them and let the user
drag them into the description (or commit them to the branch).

### 5. Push and open the PR as a draft

No approval step — push and open directly, but **always as a draft** (`--draft`).
Push the branch the worktree is already on, and pass the body inline (a heredoc
keeps it readable); do not route it through a file:

```bash
(cd dev/<repo> && git push -u fork HEAD && gh pr create --draft --title "<title>" --body "$(cat <<'EOF'
<the short body you wrote in step 4>
EOF
)")
```

### 6. Label the PR for the changelog (best-effort)

Every repo has a workflow that requires each PR to carry a label so the changelog
builds correctly. After opening, list the repo's available labels and apply the
most fitting one:

```bash
(cd dev/<repo> && gh label list)                              # see what this repo offers (e.g. enhancement, bug, maintenance, documentation)
(cd dev/<repo> && gh pr edit <pr-number> --add-label "<chosen-label>")
```

Pick the label that matches the change (a fix → `bug`, a feature → `enhancement`,
docs → `documentation`, chores/deps → `maintenance`, mapping to whatever the repo
actually lists). **If labeling fails (e.g. missing permission), ignore it and move
on** — do not try to fix it. We may not have label permissions on every repo.

### 7. Watch CI to green before notifying

Watch the PR's checks and only notify the user once CI is green:

```bash
(cd dev/<repo> && gh pr checks --watch)
```

- **CI green** → notify success (step 9 of the workspace workflow: `cmux notify --title "Done: <ws>" …`).
- **CI failing** → try to fix the failure, push the fix, and let the watch re-run.
- **Stuck** (can't figure out the failure after a genuine attempt) → **abort and
  notify** with the blocker: `cmux notify --title "Stuck: <ws>" --body "<what's red + why>"`.
  Don't spin indefinitely.

## Full Example

```bash
# From the workspace root: ensure the fork + default repo are set up
just dev ensure-fork jupyter-ai-router

# The dev/jupyter-ai-router worktree is already on its task branch — just commit.
# Run repo-scoped commands in a subshell so PWD stays the workspace root.
(cd dev/jupyter-ai-router && git add -A && git commit -m "Route messages by metadata")

# Push and open as a draft (no approval needed), body written inline and kept short
(cd dev/jupyter-ai-router && git push -u fork HEAD && gh pr create --draft \
  --title "Route messages by metadata, and drop the active-persona concept" \
  --body "$(cat <<'EOF'
## Motivation

Messages used to route to personas by `@`-mention, which was easy to forget and
broke auto-responses in multi-user chats. See #43.

## Summary

Each message now names its target persona in its own metadata, so different users
can address different personas in the same chat. Mostly reverts #54.

Fixes #43
EOF
)")

# Label for the changelog (best-effort; ignore failures)
(cd dev/jupyter-ai-router && gh label list)
(cd dev/jupyter-ai-router && gh pr edit <pr-number> --add-label "enhancement")

# Watch CI to green, then notify
(cd dev/jupyter-ai-router && gh pr checks --watch)
```

## Notes

- Agents may open PRs freely, but **always as drafts** (`--draft`). Do NOT mark a
  PR ready-for-review or merge it without the user.
- The worktree is already on its own branch — don't create one, and never push to `main`
- Run repo-scoped `git`/`gh` commands inside `(cd dev/<repo> && …)` — don't assume PWD is the repo
- The `fork` remote points to your personal fork; `origin` points to the upstream repo
- Labeling and CI-watching are part of opening a PR — don't stop at `gh pr create`.
- Keep the body short and unformatted-looking (see step 4). No `PR.md` file, no
  wall of bold, no line numbers, blank lines between paragraphs only.
