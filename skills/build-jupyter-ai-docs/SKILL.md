---
name: build-jupyter-ai-docs
description: Preview a subpackage's contributor/developer docs in the aggregated jupyter-ai site before releasing. Use when you've added or edited docs/source/{contributors,developers}/ in a jupyter-ai-contrib subpackage and want to see them render on the main Jupyter AI docs site.
---

# Build the aggregated Jupyter AI docs

Each `jupyter-ai-contrib` subpackage can ship its own **contributor** and
**developer** docs (under `docs/source/{contributors,developers}/`). The main
`jupyter-ai` Read the Docs site pulls these in as versioned subpages via git
submodules that are aggregated by a Sphinx hook.

The catch: the published site pins each submodule to its **latest released
tag**, so normally your docs would only appear after you cut a release. This
skill lets you preview your **uncommitted, unreleased** docs in the real
aggregated build first, by overlaying your live `dev/<repo>/docs/` into the
build. Nothing is committed and nothing in your checkout is modified.

## When to use

- You added or edited `docs/source/contributors/index.md` and/or
  `docs/source/developers/index.md` (± nested pages/images) in a subpackage.
- You want to confirm they render correctly on the main Jupyter AI site — title,
  toctree nesting, images, cross-references — **before releasing**.

## Prerequisites

The build aggregates docs from `dev/jupyter-ai`, so it must be dev-installed. If
you don't already have it:

```bash
just dev add jupyter-ai
uv sync
```

`dev/jupyter-ai` also needs to be on a branch that has the docs-submodule
infrastructure (`submodules/manifest.json` + `docs/source/_ext/subpackage_docs.py`).
This is on `main` as of the "submodule docs infrastructure" PR.

Your subpackage must **also** be dev-installed (`just dev add <repo>`) so its
live `docs/` is on disk — that is what gets previewed.

## Steps

### 1. Install the docs build dependencies (once per venv)

The Sphinx theme + extensions (and Sphinx itself, which `docs/requirements.txt`
omits, matching Read the Docs) are not in the base venv. Install them once:

```bash
just dev docs-deps
```

If you skip this, the build step fails with `sphinx-build not found`.

### 2. Write your docs in the subpackage

Inside `dev/<your-repo>/`, create either or both sections. An `index.md` is
**required** in each section you want to surface (its H1 becomes the subpage
title on the main site; the repo name is the recommended title). You may ship a
full subtree — nested pages and images — structured by your `index.md`'s own
`{toctree}`:

```
dev/<your-repo>/docs/source/contributors/
├── index.md          # required; H1 = subpage title
├── some-topic.md
└── _static/diagram.png
```

### 3. Build the aggregated site

```bash
just dev build-jai-docs
```

This overlays every dev-installed subpackage's live `docs/` into the aggregation
build, runs `sphinx-build`, and prints the output path. It then **restores** the
submodule trees and removes generated staging dirs, so your working tree is left
pristine regardless of success or failure. Your subpackage's `docs/` files are
never touched.

### 4. Inspect the result

Open the printed `file://…/index.html` and confirm:

- Your subpackage appears under **Contributors** and/or **Developers**.
- Its title (your `index.md` H1) is correct.
- Nested pages and images render and links resolve.

Iterate on the docs in `dev/<your-repo>/docs/` and re-run `just dev build-jai-docs`
as needed.

## Notes

- **Nothing is committed.** The overlay is temporary and reverted on exit. Commit
  your docs to the subpackage repo as normal when you're happy; they appear on
  the live site after a release + the "Update submodule documentation" workflow
  re-pins the submodule.
- If no dev-installed subpackage ships `docs/`, the recipe still builds the base
  site (a useful smoke test) and says so.
- A section directory without an `index.*` is silently skipped — add one to
  anchor the subpage.
- The build reuses jupyter-ai's real `conf.py`, theme, and extensions, so what
  you see is what the published site will render.
