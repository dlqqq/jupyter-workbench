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

- Changes committed on a branch in the repo
- `gh` CLI authenticated

## Steps

### 1. Ensure fork exists

From the workspace root:

```bash
just dev ensure-fork <repo-name>
```

This creates a GitHub fork (if needed) and sets up the `fork` remote + `gh repo set-default` for `dev/<repo-name>`.

### 2. Create a branch (if not already on one)

```bash
git checkout -b <branch-name>
```

Use a descriptive branch name, e.g., `fix-chat-input-fill` or `add-windows-subprocess-support`.

### 3. Commit your changes

```bash
git add -A
git commit -m "<concise description of changes>"
```

### 4. Include screenshots (if relevant)

If the change has visual impact, include any screenshots you saved under
`screenshots/` during testing, and reference them in `PR.md` as
`![description](screenshots/filename.png)`.

### 5. Write PR.md preview

Write a `PR.md` file in the workspace root with the full PR description. Include:
- Title (first `# heading`)
- Description of changes
- Screenshots referenced as `![description](screenshots/filename.png)`
- Issue references (e.g., `Fixes #123`)

Example:
```markdown
# Fix chat input fill when autosend is false

## Summary
When `autoSend` is false, the `openWithMessage` command now fills the chat input
with the message text instead of just focusing the empty input.

## Changes
- Modified `ChatWidget` to set input value via the input model
- Added unit test for the new behavior

## Screenshots
![Before - empty input](screenshots/before.png)
![After - input filled](screenshots/after.png)

Fixes jupyterlab/jupyter-chat#400
```

### 6. Push and open the PR as a draft

No approval step — push and open directly, but **always as a draft** (`--draft`):

```bash
git push -u fork <branch-name>

gh pr create \
  --draft \
  --title "<title from PR.md>" \
  --body "$(cat PR.md | tail -n +2)"
```

Note: Screenshots referenced in PR.md won't render on GitHub (they're local paths). The user can drag-drop them into the PR description after it's created, or they can be committed to the branch.

### 7. Label the PR for the changelog (best-effort)

Every repo has a workflow that requires each PR to carry a label so the changelog
builds correctly. After opening, list the repo's available labels and apply the
most fitting one:

```bash
gh label list                 # see what this repo offers (e.g. enhancement, bug, maintenance, documentation)
gh pr edit <pr-number> --add-label "<chosen-label>"
```

Pick the label that matches the change (a fix → `bug`, a feature → `enhancement`,
docs → `documentation`, chores/deps → `maintenance`, mapping to whatever the repo
actually lists). **If labeling fails (e.g. missing permission), ignore it and move
on** — do not try to fix it. We may not have label permissions on every repo.

### 8. Watch CI to green before notifying

Watch the PR's checks and only notify the user once CI is green:

```bash
cd dev/<repo> && gh pr checks --watch
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

# Work inside the dev worktree
cd dev/jupyter-ai-router
git checkout -b fix-priority-routing
git add -A
git commit -m "Fix priority routing for multiple personas"

# Write PR.md with description + screenshots
cat > PR.md << 'EOF'
# Fix priority routing for multiple personas

## Summary
Routes messages to the correct persona when multiple are active.

## Screenshots
![Fix applied](screenshots/after.png)

Fixes #42
EOF

# Push and open as a draft (no approval needed)
git push -u fork fix-priority-routing
gh pr create --draft --title "Fix priority routing for multiple personas" --body "$(cat PR.md | tail -n +2)"

# Label for the changelog (best-effort; ignore failures)
gh label list
gh pr edit <pr-number> --add-label "bug"

# Watch CI to green, then notify
cd dev/jupyter-ai-router && gh pr checks --watch
```

## Notes

- Agents may open PRs freely, but **always as drafts** (`--draft`). Do NOT mark a
  PR ready-for-review or merge it without the user.
- Do NOT push to `main` — always use a feature branch
- The `fork` remote points to your personal fork; `origin` points to the upstream repo
- Labeling and CI-watching are part of opening a PR — don't stop at `gh pr create`.
