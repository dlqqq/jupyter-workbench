root := justfile_directory()

# Check if a server is running
status:
    @jq -r '.server.url // empty' "{{ root }}/.workspace_info.json"

# Start JupyterLab in a new tab
start *args:
    #!/usr/bin/env bash
    set -eo pipefail
    root="{{ root }}"

    existing=$(jq -r '.server.url // empty' "$root/.workspace_info.json")
    if [[ -n "$existing" ]]; then
        echo "Error: a Jupyter server is already running at $existing" >&2
        echo "Use 'just server restart' to restart it." >&2
        exit 1
    fi

    pane=$(cmux identify --json | jq -r '.caller.pane_ref')
    surface_json=$(cmux new-surface --workspace "${CMUX_WORKSPACE_ID}" --pane "$pane" --type terminal --focus false --json)
    server_surface=$(echo "$surface_json" | jq -r '.surface_ref')

    cmux send --workspace "${CMUX_WORKSPACE_ID}" --surface "$server_surface" "cd $root && source .venv/bin/activate && jupyter lab --no-browser --expose-app-in-browser --config=./jupyter_server_config.py {{ args }}\n"

    echo "Waiting for server to start..."
    for i in {1..30}; do
        sleep 1
        server_json=$(jupyter server list --jsonlist 2>/dev/null | jq --arg root "$root" '[.[] | select(.root_dir == $root)] | .[0] // empty')
        if [[ -n "$server_json" && "$server_json" != "null" ]]; then
            url=$(echo "$server_json" | jq -r '.url')
            token=$(echo "$server_json" | jq -r '.token')
            break
        fi
    done

    if [[ -z "$url" ]]; then
        echo "Error: server did not start within 30 seconds" >&2
        exit 1
    fi

    pid=$(echo "$server_json" | jq -r '.pid')
    pgid=$(ps -o pgid= -p "$pid" | tr -d ' ')
    jq --arg sid "$server_surface" --arg url "$url" --arg token "$token" --arg pid "$pid" --arg pgid "$pgid" \
        '.server = {"surface_id": $sid, "url": $url, "token": $token, "pid": ($pid | tonumber), "pgid": ($pgid | tonumber)}' \
        "$root/.workspace_info.json" > "$root/.workspace_info.json.tmp" \
        && mv "$root/.workspace_info.json.tmp" "$root/.workspace_info.json"

    echo "✓ JupyterLab running at ${url}lab?token=${token}"

# Stop the JupyterLab server
stop:
    #!/usr/bin/env bash
    set -eo pipefail
    root="{{ root }}"

    server_pgid=$(jq -r '.server.pgid // empty' "$root/.workspace_info.json")
    server_surface=$(jq -r '.server.surface_id // empty' "$root/.workspace_info.json")

    if [[ -z "$server_pgid" ]]; then
        echo "Error: no server is running in this workspace." >&2
        exit 1
    fi

    echo "Stopping server..."
    kill -TERM -- -"$server_pgid" 2>/dev/null || true

    for i in {1..12}; do
        if ! kill -0 -- -"$server_pgid" 2>/dev/null; then
            [[ -n "$server_surface" ]] && cmux close-surface --surface "$server_surface" 2>/dev/null || true
            jq '.server = null' "$root/.workspace_info.json" > "$root/.workspace_info.json.tmp" \
                && mv "$root/.workspace_info.json.tmp" "$root/.workspace_info.json"
            echo "✓ Server stopped"
            exit 0
        fi
        sleep 0.25
    done

    echo "Server didn't stop gracefully within 3s, force killing..."
    kill -9 -- -"$server_pgid" 2>/dev/null || true
    [[ -n "$server_surface" ]] && cmux close-surface --surface "$server_surface" 2>/dev/null || true
    jq '.server = null' "$root/.workspace_info.json" > "$root/.workspace_info.json.tmp" \
        && mv "$root/.workspace_info.json.tmp" "$root/.workspace_info.json"
    echo "✓ Server force killed"

# Restart server and navigate browser to new URL
restart:
    #!/usr/bin/env bash
    set -eo pipefail
    root="{{ root }}"
    just server stop
    just server start
    surface=$(jq -r '.browser.surface_id // empty' "$root/.workspace_info.json")
    if [[ -n "$surface" ]]; then
        url=$(jq -r '.server.url // empty' "$root/.workspace_info.json")
        token=$(jq -r '.server.token // empty' "$root/.workspace_info.json")
        cmux browser "$surface" goto "${url}lab?token=${token}"
    fi
