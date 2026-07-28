# Superreleaser — conda-forge release DAG (Apache Airflow)

Automates the **conda-forge feedstock release** for a single Jupyter AI
subpackage as a linear, human-gated Airflow 3 DAG. Trigger it, it opens the
feedstock PR for you, waits for CI, and pauses for your approval **in the
Airflow UI** — approve or reject there, no talking to an agent.

> Rebuilt from the earlier Prefect spike (preserved in
> `../tmp/superreleaser-prefect/`). Airflow was chosen here to evaluate its
> **first-class Human-in-the-Loop** support (`ApprovalOperator`, `awaiting_input`
> state) introduced in Airflow 3.1.

## What it does (`cf_release` DAG)

Triggered with a conf like `{"package": "jupyter-ai-acp-client"}`:

| Task | Step |
|------|------|
| `checkout` | Sync the `<pkg>-feedstock` submodule to its remote default branch. |
| `pick_version` | Pick the **earliest STABLE** PyPI version missing from the feedstock (one bump per PR, conda-forge convention; prereleases skipped). Skips if caught up. |
| `update_recipe` | Set `context.version`, `source.sha256` (from the PyPI sdist), and rewrite `requirements.run` from the **released package's own metadata** (version ranges sorted floor-first). Logs the full `git diff` of the recipe. |
| `verify_cf` | For every run dep: the conda-forge package **exists** *and* the required **version range resolves** to a build. Doesn't hard-fail — unmet ranges are surfaced in the PR body and the approval gate. |
| `open_pr` | Push a branch and open the feedstock PR + `@conda-forge-admin, please rerender`. **DRAFT** (with an explanatory comment) if any dep was unresolved; a normal PR otherwise. **Never auto-merges.** |
| `wait_for_ci` | `PythonSensor` (reschedule mode) polling the PR's checks to pass/fail. |
| `build_gate_body` + `approval` | `ApprovalOperator` — review the PR in the UI and **Approve/Reject**. Reject fails the run. |

### The dependency-mapping problem (the hard part)

conda-forge package names are **not** a deterministic transform of PyPI names —
verified against `api.anaconda.org`:

| PyPI name | conda-forge name |
|-----------|------------------|
| `jupyter-server` | `jupyter_server` (**underscore**) |
| `jupyterlab-chat` | `jupyterlab-chat` (hyphen) |
| `agent-client-protocol` | `agent-client-protocol` (hyphen) |

So names are **probed, never guessed** (`superreleaser/condaforge.py::resolve_conda_name`):

1. A dep **already in the recipe** keeps its (correct) conda name; only its
   version range is refreshed.
2. A **new** dep is looked up on conda-forge (as-is, hyphenated, underscored).
   Found → added. **Not found → tracked as `unresolved`**: the dep is *not*
   added, the PR is opened as a **draft**, and a comment is posted naming the
   PyPI dependency for a maintainer to map by hand.

This "continue but track state, then comment on the PR" behavior is the core
requirement — a missing mapping never silently drops a dependency or aborts the
release.

## Layout

```
airflow-superreleaser/
├── dags/cf_release.py        # the DAG (orchestration only)
└── superreleaser/            # Airflow-independent logic (unit-testable)
    ├── config.py             # paths + DRY_RUN default
    ├── condaforge.py         # anaconda.org + PyPI probes, name resolution
    ├── recipe.py             # recipe read/edit + version selection + dep mapping
    └── gitops.py             # git/gh ops (dry-run aware)
```

## Run it locally (single user, SQLite)

Airflow **3.1+** required (built/tested on 3.3.0). From the workspace root with
the venv active:

```bash
cd airflow-superreleaser
export AIRFLOW_HOME=$PWD/airflow_home
export AIRFLOW__CORE__DAGS_FOLDER=$PWD/dags
export AIRFLOW__CORE__LOAD_EXAMPLES=False

# All-in-one local server on SQLite (API server + scheduler + triggerer).
# Prints an admin password to simple_auth_manager_passwords.json.generated.
airflow standalone
```

Open the UI (http://localhost:8080), then trigger `cf_release` with a conf:

```json
{ "package": "jupyter-ai-acp-client", "dry_run": true }
```

- `dry_run: true` → edits the local recipe but **prints** the branch/push/PR/
  comment commands instead of running them. Safe to walk the whole DAG.
- omit `dry_run` (or `false`) → **opens a real feedstock PR** (+ rerender
  comment). Still never merges — you merge after approving.
- `version: "0.2.0"` → force a specific target instead of earliest-missing.

At the `approval` task the run enters `awaiting_input`; open it in the UI and
click **Approve** or **Reject**.

## Guardrails

- **No auto-merge, ever.** The DAG opens/annotates the PR and gates; a human
  merges on conda-forge after approving.
- `gh` auth comes from your shell. `AIRFLOW_HOME` (SQLite DB, logs, generated
  password) stays out of version control.
