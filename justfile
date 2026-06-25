set dotenv-load := true

root := justfile_directory()

mod repos
mod dev
mod ws 'workspaces'
mod server
mod browser

alias list := list-recipes
alias restart := server::restart

# List all available recipes
list-recipes:
    @just --list --list-heading=""

# Run full workspace setup (create dev worktrees, install, enable extensions)
setup-workspace:
    #!/usr/bin/env bash
    set -eo pipefail
    ws_name=$(basename "{{ root }}")
    trap 'cmux notify --title "Setup failed: $ws_name" --body "$BASH_COMMAND exited with $?"' ERR
    just dev setup
    just sync

# Start server and open browser
start: server::start browser::open

# Alias for `uv sync`
sync *args:
    uv sync

# Add packages via uv (comma-separated)
add pkgs:
    #!/usr/bin/env bash
    set -eo pipefail
    IFS=',' read -ra packages <<< "{{ pkgs }}"
    uv add "${packages[@]}"

# Show which packages are dev-installed in this workspace
status:
    #!/usr/bin/env bash
    set -eo pipefail
    echo "Dev-installed repos:"
    jq -r '.["dev-repos"] | keys[]' "{{ root }}/.workspace_info.json"

# Spawn an agent session using the prompt from .workspace_info.json
spawn-agent:
    #!/usr/bin/env bash
    set -eo pipefail
    root="{{ root }}"
    prompt=$(jq -r '.prompt // empty' "$root/.workspace_info.json")
    pgid=$(ps -o pgid= -p $$ | tr -d ' ')
    jq --arg pgid "$pgid" '.agent = {"pgid": ($pgid | tonumber)}' \
        "$root/.workspace_info.json" > "$root/.workspace_info.json.tmp" \
        && mv "$root/.workspace_info.json.tmp" "$root/.workspace_info.json"
    source "$root/.venv/bin/activate"
    exec kiro-cli chat --agent dlq -a "$prompt"

# Stop the agent session
stop-agent:
    #!/usr/bin/env bash
    set -eo pipefail
    root="{{ root }}"

    agent_pgid=$(jq -r '.agent.pgid // empty' "$root/.workspace_info.json")
    if [[ -z "$agent_pgid" ]]; then
        echo "Error: no agent is running in this workspace." >&2
        exit 1
    fi

    echo "Stopping agent..."
    kill -TERM -- -"$agent_pgid" 2>/dev/null || true

    for i in {1..12}; do
        if ! kill -0 -- -"$agent_pgid" 2>/dev/null; then
            jq '.agent = null' "$root/.workspace_info.json" > "$root/.workspace_info.json.tmp" \
                && mv "$root/.workspace_info.json.tmp" "$root/.workspace_info.json"
            echo "✓ Agent stopped"
            exit 0
        fi
        sleep 0.25
    done

    echo "Agent didn't stop within 3s, force killing..."
    kill -9 -- -"$agent_pgid" 2>/dev/null || true
    jq '.agent = null' "$root/.workspace_info.json" > "$root/.workspace_info.json.tmp" \
        && mv "$root/.workspace_info.json.tmp" "$root/.workspace_info.json"
    echo "✓ Agent force killed"

# Close this workspace (stop agent + server, close cmux workspace)
close:
    #!/usr/bin/env bash
    set -eo pipefail
    root="{{ root }}"

    agent_pgid=$(jq -r '.agent.pgid // empty' "$root/.workspace_info.json")
    if [[ -n "$agent_pgid" ]] && kill -0 -- -"$agent_pgid" 2>/dev/null; then
        just stop-agent
    fi

    server_pgid=$(jq -r '.server.pgid // empty' "$root/.workspace_info.json")
    if [[ -n "$server_pgid" ]] && kill -0 -- -"$server_pgid" 2>/dev/null; then
        just server stop
    fi

    cmux close-workspace --workspace "${CMUX_WORKSPACE_ID}"
