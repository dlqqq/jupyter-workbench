---
name: rebuild-frontend
description: Rebuild frontend extensions after TypeScript/CSS changes. Use when you've modified frontend files (.ts, .tsx, .css) in one or more packages and need to see the changes in JupyterLab.
---

# Rebuild Frontend

Rebuild JupyterLab frontend extensions after making changes to TypeScript, CSS, or other frontend files.

## When to Use

- After modifying `.ts`, `.tsx`, `.css`, or other frontend source files
- NOT needed for backend-only changes (`.py` files) — those require a server restart instead

## Steps

### 0. Reinstall dependencies (only if needed)

If `package.json` or `yarn.lock` has changed (e.g., after pulling new changes or adding a dependency), reinstall first:

```bash
cd <package>/ && just jlpm
```

`jlpm` is JupyterLab's bundled version of yarn. Skip this step if you only changed source files.

### 1. Rebuild

**Single package:**
```bash
cd <package>/ && just build
```

**All packages in the worktree:**
```bash
just build-all
```

Only rebuild packages whose frontend files have actually changed. If you're unsure which packages changed, `just build-all` is safe but slower.

### 2. Reload the browser

After rebuilding, reload the JupyterLab page so it picks up the new assets:

```bash
SURFACE=$(just get-browser-surface)
cmux browser $SURFACE reload
```

If no browser is open, skip this step — the next time JupyterLab is opened it will load the rebuilt extensions.

## Summary

| What changed | Action |
|---|---|
| `.ts`/`.tsx`/`.css` files | `just build` (in the repo) + reload browser |
| `package.json` or `yarn.lock` | `just jlpm` (in the repo) + `just build` + reload browser |
| `.py` files only | No frontend rebuild needed (restart server instead) |
