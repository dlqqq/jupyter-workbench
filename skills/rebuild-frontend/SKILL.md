---
name: rebuild-frontend
description: Rebuild frontend extensions after TypeScript/CSS changes. Use when you've modified frontend files (.ts, .tsx, .css) in a dev-installed package and need the changes reflected in JupyterLab or before running E2E tests.
---

# Rebuild Frontend

Rebuild a JupyterLab frontend extension after editing TypeScript, CSS, or other
frontend source files. The workspace venv is already activated, so you run the
package's own tooling directly inside its `dev/` worktree.

## When to Use

- After modifying `.ts`, `.tsx`, `.css`, or other frontend source files in `dev/<repo>`
- **Before running E2E (Galata) tests** for a package — the tests load the built assets
- NOT needed for backend-only changes (`.py` files)

## Steps

### 0. Reinstall JS deps (only if needed)

If `package.json` or `yarn.lock` changed (e.g. after pulling or adding a dependency):

```bash
(cd dev/<repo-name> && jlpm)
```

`jlpm` is JupyterLab's bundled yarn. Skip this if you only changed source files.

### 1. Rebuild

```bash
(cd dev/<repo-name> && jlpm build)
```

Run this for each dev package whose frontend files changed. Always rebuild
before invoking that package's E2E tests.

## Summary

| What changed | Action |
|---|---|
| `.ts`/`.tsx`/`.css` files | `(cd dev/<repo> && jlpm build)` |
| `package.json` / `yarn.lock` | `(cd dev/<repo> && jlpm)` then `jlpm build` |
| `.py` files only | No frontend rebuild needed |

## Notes

- Verifying the change in a live browser is being migrated to JupyterLab's
  Galata (Playwright) E2E framework. Prefer adding/running an E2E test over
  manual visual inspection where the repo supports it.
