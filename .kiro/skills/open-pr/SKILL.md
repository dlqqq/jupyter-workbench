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

### 4. Push to your fork

```bash
git push -u fork <branch-name>
```

### 5. Open the PR

```bash
gh pr create --title "<title>" --body "<description>"
```

The PR will target the upstream repo (set by `gh repo set-default` in step 1).

Tips for the PR body:
- Reference the issue (e.g., `Fixes #123`)
- Summarize what was changed and why
- Note any testing done

## Full Example

```bash
cd jupyter-ai-router

# Ensure fork
just ensure-fork

# Branch, commit, push
git checkout -b fix-priority-routing
git add -A
git commit -m "Fix priority routing for multiple personas"
git push -u fork fix-priority-routing

# Open PR
gh pr create \
  --title "Fix priority routing for multiple personas" \
  --body "Fixes #42. Routes messages to the correct persona when multiple are active."
```

## Notes

- Do NOT open a PR unless the user explicitly asks
- Do NOT push to `main` — always use a feature branch
- The `fork` remote points to your personal fork; `origin` points to the upstream repo
