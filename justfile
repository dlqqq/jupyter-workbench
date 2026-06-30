set dotenv-load := true

root := justfile_directory()

mod repos
mod dev
mod ws 'workspaces'
mod workbench 'workbench.just'
mod server
mod browser
mod workbench-tests

alias list := list-recipes
alias restart := server::restart

# List all available recipes
list-recipes:
    @just --list --list-heading=""

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

# Show which repos are dev-installed in this workspace (scans ./dev)
status:
    #!/usr/bin/env bash
    set -eo pipefail
    echo "Dev-installed repos:"
    for d in "{{ root }}"/dev/*/; do
        [[ -d "$d" ]] || continue
        echo "  $(basename "$d")"
    done

# Spawn the workspace agent (reads PLAN.md for its task; prompt is fixed)
spawn-agent:
    #!/usr/bin/env bash
    set -eo pipefail
    root="{{ root }}"
    name="$(basename "$root")"

    # The worker prompt is a fixed template — the only variable is the workspace
    # name, derived from the directory. The actual task lives in PLAN.md, written
    # to disk as a file (never passed through shell-argument quoting). This is the
    # whole point: free-form text goes in files, never in flags.
    prompt="You are the workspace agent for the $name workspace under the Jupyter Workbench. First, read AGENTS.md if it is not already in your context — it describes the recipes, skills, and workflow for working in a workspace. Then read PLAN.md for your task. Gather context and do research first; if anything is still unclear, grill the user using the grill-me skill before writing code. Follow the workflow in AGENTS.md, dispatching subagents for independent work where it helps. Open a PR for each affected repo when done. Notify the user once you are complete or get stuck."

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
