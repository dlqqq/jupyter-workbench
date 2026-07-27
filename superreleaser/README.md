# Superreleaser (spike)

A local, human-gated release orchestrator for Jupyter AI, built on **self-hosted
Prefect 3**. It runs the real release steps for a subpackage — trigger the GitHub
release workflows, await PyPI, open the conda-forge feedstock PR — and **pauses at
durable gates** where a human approves or rejects **in the Prefect UI**, not by
talking to the agent. Because paused state lives in Prefect's SQLite DB, a release
survives you closing the Claude terminal.

> **Spike status.** Everything is code-complete and defaults to **dry-run**: the
> destructive atoms (prep-release push, PyPI/NPM publish, feedstock PR open +
> merge) log the exact command they *would* run and return a plausible result, so
> the entire DAG — including both gates — can be exercised end-to-end **without
> shipping a real release**. Only the gates suspend for real.

## Architecture

Three roles, decoupled — the agent never owns the server:

1. **`prefect server start`** — API + UI at `127.0.0.1:4200` (SQLite, no Postgres).
2. **`serve()` executor** (`python -m superreleaser.serve`) — registers the three
   fixed deployments *once* and executes runs locally (including resuming gated
   runs after you approve in the UI).
3. **Trigger / observer** (agent or human) — just hits the running server's API
   via the `prefect` CLI / Python client.

**Data-driven, not code-generating.** Three deployments are registered once and
never regenerated. A release is just *data* (a `plan`) fed to `release-batch`.

| Deployment | What it does |
|---|---|
| `release-subpackage` | The building block. Params: `package`, `version_spec`, `branch`, `dry_run`, `include_feedstock`. Prep → **gate** → publish → PyPI → (stable only) hand off to `release-feedstock`. |
| `release-feedstock` | The conda-forge leg, **independently triggerable**. Update recipe → PR + rerender → CI → **gate** → merge → await conda-forge. |
| `release-batch` | Orchestrator. Takes a `plan` (ordered waves; each wave's subpackages run concurrently, waves run sequentially, metapackage last) and fans out one `release-subpackage` run per entry. |

## The `release-subpackage` steps

Modeled on the real workflows (`prep-release.yml` = Step 1, `publish-release.yml`
= Step 2, both `workflow_dispatch`):

1. `gh workflow run "Step 1: Prep Release"` (`version_spec`, `branch`,
   `since_last_stable` — **True** for stable, **False** for prereleases), watch to
   completion.
2. Await the draft GitHub release; capture its URL.
3. **GATE:** review the draft changelog (clickable release URL in the Markdown
   description). Reject ⇒ stop, publish nothing.
4. `gh workflow run "Step 2: Publish Release"`, watch to green. *(dry-run by default)*
5. Await PyPI: poll `pypi.org/pypi/<pkg>/<version>/json` for the sdist; capture its
   sha256 (the signal the feedstock hash can be computed).
6. → hand off to **`release-feedstock`** — **stable releases only** (skipped for
   prereleases and when `include_feedstock=false`).

## The `release-feedstock` steps (conda-forge leg)

6. Deterministically update `recipe/recipe.yaml`: `context.version`,
   `source.sha256` (from the PyPI sdist), and `requirements.run` ranges **derived
   from the released package's own metadata** (`requires_dist`) mapped to conda
   names (identity modulo `_`↔`-`). A dependency with no obvious conda mapping is
   **not guessed** — it's surfaced at the gate for a human. Reuses
   `~/workplace/jupyter-ai-feedstocks/scripts/update_version_and_hash.py`.
7. Open the feedstock PR; post `@conda-forge-admin, please rerender`. *(dry-run)*
8. Await feedstock CI.
9. **GATE:** review the PR diff. Reject ⇒ stop. On approval, merge *(dry-run)* and
   await availability on conda-forge (poll anaconda.org).

## Usage loop

```bash
# 1. Bring up server + executor + dashboard (standing services).
just superreleaser start

# 2. Trigger a dry-run single-subpackage release — reaches the changelog gate,
#    then PAUSES. Watch it in the dashboard.
just superreleaser trigger-demo            # jupyter-ai-acp-client v0.2.2, dry-run

# …or fan out a whole plan:
just superreleaser trigger-batch           # uses superreleaser/sample_plan.json

# 3. Approve/reject at the gate IN THE PREFECT UI: open the paused flow run →
#    "Resume" → set approve=true/false. The executor picks it up and continues.
```

### Running without cmux (plain terminals)

Each in its own shell, from the workspace root with the venv active:

```bash
# Terminal A — server
source .venv/bin/activate && prefect server start --host 127.0.0.1 --port 4200

# Terminal B — executor (registers all three deployments)
source .venv/bin/activate
PREFECT_API_URL=http://127.0.0.1:4200/api python -m superreleaser.serve

# Terminal C — trigger a dry run, then open http://127.0.0.1:4200 to watch + gate
source .venv/bin/activate
export PREFECT_API_URL=http://127.0.0.1:4200/api
prefect deployment run 'release-subpackage/release-subpackage' \
  -p package=jupyter-ai-acp-client -p version_spec=v0.2.2 -p branch=main -p dry_run=true
```

## Guardrails

- **Nothing ships in dry-run** (the default). Flip a single atom to real only with
  `dry_run=false`, and confirm with the maintainer before doing so.
- Secrets stay out of the repo; `gh` auth comes from your shell. Prefect's SQLite
  DB lives in `~/.prefect`, outside version control.

## Files

- `flows.py` — the three flows + the `GateDecision` suspend input.
- `steps.py` — Step 1–5 atoms (prep, await-draft, publish, await-PyPI).
- `feedstock.py` — Step 6–9 atoms (recipe update, PR, CI, merge, await-conda).
- `serve.py` — the `serve()` entrypoint registering all three deployments.
- `config.py` — names/paths/dry-run default (data only).
- `sample_plan.json` — example two-wave batch plan.
