root := justfile_directory()

# Airflow project dir + a single AIRFLOW_HOME under it (SQLite db, logs, config).
af := root / "airflow-superreleaser"

# Start Airflow (all-in-one: API server + scheduler + triggerer) on SQLite, with
# auth disabled for localhost-only use. Foreground/long-lived — leave it running,
# then open http://localhost:8080 and trigger the `cf_release` DAG.
[group('superreleaser')]
airflow:
    #!/usr/bin/env bash
    set -eo pipefail
    export AIRFLOW_HOME="{{ af }}/airflow_home"
    export AIRFLOW__CORE__DAGS_FOLDER="{{ af }}/dags"
    export AIRFLOW__CORE__LOAD_EXAMPLES=False
    export AIRFLOW__CORE__SIMPLE_AUTH_MANAGER_ALL_ADMINS=True
    echo "Airflow UI → http://localhost:8080 (auth disabled; localhost only)"
    exec "{{ root }}/.venv/bin/airflow" standalone

# Trigger the cf_release DAG for a package (dry-run by default). Airflow must be
# running (`just superreleaser airflow`). Force a target with version=0.2.0.
[group('superreleaser')]
cf-release package version="" dry_run="true":
    #!/usr/bin/env bash
    set -eo pipefail
    export AIRFLOW_HOME="{{ af }}/airflow_home"
    export AIRFLOW__CORE__DAGS_FOLDER="{{ af }}/dags"
    conf=$(printf '{"package":"%s","version":"%s","dry_run":%s}' "{{ package }}" "{{ version }}" "{{ dry_run }}")
    echo "conf: $conf"
    "{{ root }}/.venv/bin/airflow" dags trigger cf_release --conf "$conf"

# Bring up the local Prefect server + serve() executor in cmux surfaces, open
# the dashboard, and print the trigger command. Server + executor are standing
# services; SQLite (~/.prefect) persists paused/gated state across sessions.
[group('superreleaser')]
start:
    #!/usr/bin/env bash
    set -eo pipefail
    root="{{ root }}"
    api="http://127.0.0.1:4200/api"
    ui="http://127.0.0.1:4200"

    pane=$(cmux identify --json | jq -r '.caller.pane_ref')

    # 1) Prefect server (API + UI) in its own surface.
    srv=$(cmux new-surface --workspace "${CMUX_WORKSPACE_ID}" --pane "$pane" --type terminal --focus false --json | jq -r '.surface_ref')
    cmux send --workspace "${CMUX_WORKSPACE_ID}" --surface "$srv" \
        "cd $root && source .venv/bin/activate && prefect server start --host 127.0.0.1 --port 4200\n"

    echo "Waiting for Prefect API at ${api} ..."
    for i in {1..60}; do
        if curl -sf "${api}/health" >/dev/null 2>&1; then break; fi
        sleep 1
    done
    if ! curl -sf "${api}/health" >/dev/null 2>&1; then
        echo "Error: Prefect server did not come up within 60s" >&2
        exit 1
    fi

    # 2) serve() executor — registers all three deployments, executes runs.
    exe=$(cmux new-surface --workspace "${CMUX_WORKSPACE_ID}" --pane "$pane" --type terminal --focus false --json | jq -r '.surface_ref')
    cmux send --workspace "${CMUX_WORKSPACE_ID}" --surface "$exe" \
        "cd $root && source .venv/bin/activate && PREFECT_API_URL=${api} python -m superreleaser.serve\n"

    # 3) Dashboard inside cmux.
    cmux browser open "${ui}/deployments" --workspace "${CMUX_WORKSPACE_ID}" >/dev/null

    echo ""
    echo "✓ Prefect server:  ${ui}"
    echo "✓ Executor:        registering release-subpackage / release-feedstock / release-batch"
    echo ""
    echo "Trigger a dry-run single-subpackage release (reaches gate 1, then pauses):"
    echo "  just superreleaser trigger-demo"
    echo ""
    echo "Approve/reject at gates IN THE PREFECT UI (Flow Run → Resume)."

# Trigger a dry-run release of jupyter-ai-acp-client (reaches the changelog gate).
[group('superreleaser')]
trigger-demo version="v0.2.2":
    #!/usr/bin/env bash
    set -eo pipefail
    cd "{{ root }}" && source .venv/bin/activate
    export PREFECT_API_URL="http://127.0.0.1:4200/api"
    prefect deployment run 'release-subpackage/release-subpackage' \
        -p package=jupyter-ai-acp-client \
        -p version_spec={{ version }} \
        -p branch=main \
        -p dry_run=true

# Trigger a dry-run release-batch from a sample two-wave plan.
[group('superreleaser')]
trigger-batch:
    #!/usr/bin/env bash
    set -eo pipefail
    cd "{{ root }}" && source .venv/bin/activate
    export PREFECT_API_URL="http://127.0.0.1:4200/api"
    plan=$(cat superreleaser/sample_plan.json)
    prefect deployment run 'release-batch/release-batch' -p plan="$plan" -p dry_run=true
