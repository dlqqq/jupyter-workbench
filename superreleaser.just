root := justfile_directory()

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
