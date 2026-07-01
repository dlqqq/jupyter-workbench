---
name: prep-jupyter-ai-release
description: Prep a jupyter-ai release by bumping subpackage version floors to their latest PyPI releases, adding breaking-version ceilings, bumping the package version, and documenting the versioning strategy. Use when preparing a new jupyter-ai release (e.g. a patch release whose purpose is to refresh dependency ranges).
---

# Prep a jupyter-ai Release

Jupyter AI is assembled from many fast-moving subpackages. A release commonly
exists to **refresh the version ranges** on those subpackages: raise each floor
to the latest released version and add a ceiling that blocks the next breaking
version, so subpackages can ship breaking changes without silently breaking
installed `jupyter-ai` environments.

This skill documents that whole process: floor bump + ceiling convention + the
package version bump + the user-facing docs note.

## When to Use

- Cutting a new `jupyter-ai` release whose purpose is to update dependency ranges
- Adding or refreshing version ceilings on subpackage dependencies
- NOT for feature/code changes — this is a dependency-and-release-hygiene workflow

## Prerequisites

- `jupyter-ai` dev-installed in the workspace (`just dev add jupyter-ai && just dev setup`)
- Network access to PyPI

## Steps

### 1. List the subpackages currently depended on

Read `dev/jupyter-ai/pyproject.toml`. Collect every subpackage in both
`[project] dependencies` and every `[project.optional-dependencies]` extra
(e.g. `magics`, `jupyternaut`). Note the current floor for each.

**Do NOT add any new packages.** Only update existing version ranges.

### 2. Look up the latest non-prerelease version of each on PyPI

For each subpackage, find the latest released version. **Skip pre-releases**
(anything with `a`/`b`/`rc`/`.dev` suffixes) and yanked releases.

```bash
# Quick check for one package:
pip index versions <pkg>

# Robust lookup that filters prereleases/yanked across all packages:
python3 - <<'EOF'
import json, urllib.request
from packaging.version import Version
pkgs = ["jupyterlab_chat", "jupyter_server_documents", "..."]  # fill in from step 1
for pkg in pkgs:
    with urllib.request.urlopen(f"https://pypi.org/pypi/{pkg}/json", timeout=30) as r:
        data = json.load(r)
    vers = []
    for v, files in data["releases"].items():
        if not files or all(f.get("yanked") for f in files):
            continue
        ver = Version(v)
        if ver.is_prerelease:
            continue
        vers.append(ver)
    print(f"{pkg}\t{max(vers)}")
EOF
```

### 3. Compute floors and ceilings

For each subpackage, set the floor to the latest released version and add a
ceiling that blocks the **next breaking version**:

- **`0.y.z` packages** (SemVer-for-0.x): the next breaking version is the next
  **minor**. Floor `0.5.2` → `>=0.5.2,<0.6.0`.
- **`>=1.0` packages**: the next breaking version is the next **major**.
  Floor `1.4.2` → `>=1.4.2,<2.0.0`.

If unsure which convention a package follows, confirm by checking how the
package versions itself (its changelog / release history — does it break on
minor or on major?).

### 4. Update `pyproject.toml`

Rewrite each existing range to `>=<latest>,<<ceiling>` in both `dependencies`
and every optional-dependencies extra. Keep packages that appear in multiple
extras (e.g. `jupyter_ai_litellm`) consistent.

### 5. Do NOT bump the package version yourself

**Leave `dev/jupyter-ai/jupyter_ai/__init__.py` `__version__` unchanged.** The
version bump is handled by our release process (`jupyter-releaser`) at release
time, not in the prep PR. This skill only **preps** the release — refreshing
dependency ranges and docs. Do not edit `__version__`.

### 6. Document the versioning strategy

Ensure `dev/jupyter-ai/docs/source/users/versioning.md` exists and is wired into
the users `index.md` toctree. It should explain, split into a **For users** and
a **For extension developers** section:

- **Versioning convention**: subpackages follow SemVer; most are `0.x`, where
  every minor release is treated as potentially breaking. Patch releases of
  `jupyter_ai` raise dependency floors (API-compatible patches); minor releases
  raise ceilings (API-breaking features). Note the support policy: older
  versions are not actively supported, and patches are backported only in
  exceptional cases (e.g. a major security vulnerability).
- **For users — upgrade frequently**: recommend upgrading as often as possible.
  Recommend an environment manager (`conda`/`mamba`/`micromamba`/`uv`/`pixi`)
  over native `pip`, whose solver is unreliable. Show upgrade commands using the
  `sphinx_tabs` `{tabs}` directive (see `getting-started.md` for the 4-backtick
  pattern).
- **For users — chat files are not forwards-compatible**: a chat made in an
  older version may not open in a newer one; workaround is to have an agent read
  and summarize the old chat file.
- **For extension developers**: add a version range around each specific
  subpackage whose API they consume, so their solver won't pull in an
  API-breaking release (only effective if they aren't using native `pip`).

### 7. Verify

```bash
# Confirm pyproject still parses:
(cd dev/jupyter-ai && python3 -c "import tomllib; tomllib.load(open('pyproject.toml','rb'))")
# Confirm __version__ is UNCHANGED (jupyter-releaser bumps it at release time):
grep __version__ dev/jupyter-ai/jupyter_ai/__init__.py
```

### 8. Open the PR

Use the `open-pr` skill to open a PR against `jupyter-ai` with the
pyproject ceilings + floors and the docs note. The PR should **not** touch
`__version__`.

## Summary

| Change | File |
|---|---|
| Floors + ceilings on subpackage deps | `dev/jupyter-ai/pyproject.toml` |
| Versioning-strategy doc + toctree | `dev/jupyter-ai/docs/source/users/versioning.md`, `index.md` |
| Package version bump | **Not done here** — handled by `jupyter-releaser` at release time |

## Notes

- Floors are the **latest released** versions; ceilings block the **next
  breaking** version (next minor for `0.x`, next major for `>=1.0`).
- Never add new dependencies in a range-refresh release — only update existing
  ranges.
- Never use pre-release versions when determining the latest version.
