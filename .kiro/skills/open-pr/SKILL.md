---
name: open-pr
description: Open a pull request from a repo in a worktree. Use when the user asks you to open a PR for your changes.
---

# Open a Pull Request

Push your changes to a fork and open a PR against the upstream repo.

## Prerequisites

- Changes committed on a branch in the repo
- `gh` CLI authenticated

## Steps

### 1. Ensure fork exists

From inside the repo:

```bash
just ensure-fork
```

This creates a GitHub fork (if needed) and sets up the `fork` remote + `gh repo set-default`.

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

### 4. Take screenshots (if relevant)

If the change has visual impact, take screenshots and save them to `screenshots/`:

```bash
mkdir -p screenshots
SURFACE=$(just get-browser-surface)
cmux browser $SURFACE screenshot --out screenshots/before.png
# ... make changes, rebuild, reload ...
cmux browser $SURFACE screenshot --out screenshots/after.png
```

### 5. Write PR.md preview

Write a `PR.md` file in the worktree root with the full PR description. Include:
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

### 6. Ask for user approval

Open the preview in cmux markdown viewer and ask the user to approve:

```bash
cmux markdown open PR.md
```

Then notify:
```bash
cmux notify --title "PR ready for review" --body "Please review PR.md and approve"
```

**Wait for the user to approve before proceeding.** Do NOT open the PR without explicit approval.

### 7. Push and open PR

After approval:

```bash
git push -u fork <branch-name>

gh pr create \
  --title "<title from PR.md>" \
  --body "$(cat PR.md | tail -n +2)"
```

Note: Screenshots referenced in PR.md won't render on GitHub (they're local paths). The user can drag-drop them into the PR description after it's created, or they can be committed to the branch.

## Full Example

```bash
cd jupyter-ai-router

# Ensure fork
just ensure-fork

# Branch and commit
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

# Preview and wait for approval
cmux markdown open PR.md
cmux notify --title "PR ready for review" --body "Please review PR.md and approve"
# ... wait for user approval ...

# Push and open
git push -u fork fix-priority-routing
gh pr create --title "Fix priority routing for multiple personas" --body "$(cat PR.md | tail -n +2)"
```

## Notes

- Do NOT open a PR unless the user explicitly asks
- Do NOT push to `main` — always use a feature branch
- The `fork` remote points to your personal fork; `origin` points to the upstream repo
