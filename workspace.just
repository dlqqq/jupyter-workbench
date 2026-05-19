set dotenv-load := true
set fallback

alias list := list-recipes
ws_root := justfile_directory()

# Echo the workspace root directory
[group('workspace')]
get-workspace-root:
    @echo "{{ ws_root }}"

# List all available recipes (including workbench)
[group('workspace')]
list-recipes:
    #!/usr/bin/env bash
    (cd "$(just get-workbench-root)" && just --list --list-heading="")
    echo ""
    just --list --list-heading=""

# Add packages via uv (comma-separated)
[group('workspace')]
[arg("pkgs", help="comma-separated packages to add")]
add pkgs:
    #!/usr/bin/env bash
    set -eo pipefail
    IFS=',' read -ra packages <<< "{{ pkgs }}"
    uv add "${packages[@]}"

# Add repos as editable (comma-separated: clone, build, dev-install)
[group('workspace')]
[arg("repos", help="comma-separated repos to dev-install")]
add-dev repos:
    #!/usr/bin/env bash
    set -eo pipefail
    ws_root="{{ ws_root }}"
    wb_root=$(just get-workbench-root)
    cd "$ws_root"

    IFS=',' read -ra repo_list <<< "{{ repos }}"
    for repo in "${repo_list[@]}"; do
    repo_name="${repo%%#*}"
    pr_number="${repo#*#}"
    [[ "$pr_number" == "$repo" ]] && pr_number=""

    url=$(jq -r --arg r "$repo_name" '.[$r].url // empty' "$wb_root/repos.json")
    if [[ -z "$url" ]]; then
        echo "Error: '$repo_name' not found in repos.json" >&2
        exit 1
    fi
    if [[ -d "$repo_name" ]]; then
        echo "Error: '$repo_name' already exists in this workspace" >&2
        exit 1
    fi

    # Clone and add as editable workspace member
    echo "Cloning $repo_name..."
    git clone "$url" "$repo_name"

    # Checkout PR if specified
    if [[ -n "$pr_number" ]]; then
        echo "Checking out PR #$pr_number..."
        (cd "$repo_name" && gh pr checkout "$pr_number")
        # Add PR author's fork as a remote
        pr_info=$(cd "$repo_name" && gh pr view "$pr_number" --json headRepositoryOwner,headRepository)
        pr_author=$(echo "$pr_info" | jq -r '.headRepositoryOwner.login')
        pr_repo=$(echo "$pr_info" | jq -r '.headRepository.name')
        fork_url="git@github.com:$pr_author/$pr_repo.git"
        (cd "$repo_name" && git remote add "$pr_author" "$fork_url" 2>/dev/null || true)
        echo "Added remote '$pr_author' → $fork_url"
    fi

    # Symlink repo justfile and exclude from git
    ln -sf "$wb_root/repo.just" "$repo_name/justfile"
    grep -qxF 'justfile' "$repo_name/.git/info/exclude" 2>/dev/null || echo 'justfile' >> "$repo_name/.git/info/exclude"

    pkg_parents=$(jq -r --arg r "$repo_name" '
        .[$r].packages // [{"parentDir": "."}]
        | .[].parentDir
    ' "$wb_root/repos.json")

    while IFS= read -r parent_dir; do
        uv add --editable --workspace "./$repo_name/$parent_dir"
    done <<< "$pkg_parents"

    # Update .workspace_info.json
    if [[ -n "$pr_number" ]]; then
        jq --arg r "$repo_name" --argjson pr "$pr_number" '.["dev-repos"][$r] = {"pr-number": $pr}' \
            "$ws_root/.workspace_info.json" > "$ws_root/.workspace_info.json.tmp"
    else
        jq --arg r "$repo_name" '.["dev-repos"][$r] = {}' \
            "$ws_root/.workspace_info.json" > "$ws_root/.workspace_info.json.tmp"
    fi
    mv "$ws_root/.workspace_info.json.tmp" "$ws_root/.workspace_info.json"

    # Enable extensions
    (cd "$repo_name"
    just enable-repo-extensions)

    echo ""
    echo "✓ Added: $repo_name"
    done

# Alias for `uv sync`
[group('workspace')]
sync *args:
    uv sync

# Show which packages are dev-installed in this workspace
[group('workspace')]
workspace-status:
    #!/usr/bin/env bash
    set -eo pipefail
    echo "Dev-installed repos:"
    jq -r '.["dev-repos"] | keys[]' "{{ ws_root }}/.workspace_info.json"

# Enable extensions for all dev-installed repos in this workspace
[group('workspace')]
enable-all-extensions:
    #!/usr/bin/env bash
    set -eo pipefail
    ws_root="{{ ws_root }}"
    repos=$(jq -r '.["dev-repos"] | keys[]' "$ws_root/.workspace_info.json")
    while IFS= read -r repo; do
        [[ -n "$repo" ]] || continue
        echo "=== $repo ==="
        (cd "$ws_root/$repo" && just enable-repo-extensions)
    done <<< "$repos"

# Build all dev-installed repos in this workspace
[group('workspace')]
build-all:
    #!/usr/bin/env bash
    set -eo pipefail
    ws_root="{{ ws_root }}"
    repos=$(jq -r '.["dev-repos"] | keys[]' "$ws_root/.workspace_info.json")
    while IFS= read -r repo; do
        [[ -n "$repo" ]] || continue
        echo "=== $repo ==="
        (cd "$ws_root/$repo" && just build)
    done <<< "$repos"

# Run full workspace setup (clone repos, install, enable extensions)
[group('workspace')]
setup-workspace:
    #!/usr/bin/env bash
    set -eo pipefail
    ws_name=$(basename "{{ ws_root }}")
    trap 'cmux notify --title "Setup failed: $ws_name" --body "$BASH_COMMAND exited with $?"' ERR
    just _clone-repos
    just enable-all-extensions
    just sync

# Clone and dev-install all repos from .workspace_info.json
[private]
_clone-repos:
    #!/usr/bin/env bash
    set -eo pipefail
    ws_root="{{ ws_root }}"
    wb_root=$(just get-workbench-root)
    cd "$ws_root"

    while IFS= read -r repo_name; do
        [[ -n "$repo_name" ]] || continue
        pr_number=$(jq -r --arg r "$repo_name" '.["dev-repos"][$r]["pr-number"] // empty' "$ws_root/.workspace_info.json")
        url=$(jq -r --arg r "$repo_name" '.[$r].url // empty' "$wb_root/repos.json")
        if [[ -z "$url" ]]; then
            echo "Error: '$repo_name' not found in repos.json" >&2
            exit 1
        fi

        echo "Cloning $repo_name..."
        git clone "$url" "$repo_name"

        if [[ -n "$pr_number" ]]; then
            echo "Checking out PR #$pr_number..."
            (cd "$repo_name" && gh pr checkout "$pr_number")
            pr_info=$(cd "$repo_name" && gh pr view "$pr_number" --json headRepositoryOwner,headRepository)
            pr_author=$(echo "$pr_info" | jq -r '.headRepositoryOwner.login')
            pr_repo=$(echo "$pr_info" | jq -r '.headRepository.name')
            fork_url="git@github.com:$pr_author/$pr_repo.git"
            (cd "$repo_name" && git remote add "$pr_author" "$fork_url" 2>/dev/null || true)
            echo "Added remote '$pr_author' → $fork_url"
        fi

        ln -sf "$wb_root/repo.just" "$repo_name/justfile"
        grep -qxF 'justfile' "$repo_name/.git/info/exclude" 2>/dev/null || echo 'justfile' >> "$repo_name/.git/info/exclude"

        pkg_parents=$(jq -r --arg r "$repo_name" '
            .[$r].packages // [{"parentDir": "."}]
            | .[].parentDir
        ' "$wb_root/repos.json")

        while IFS= read -r parent_dir; do
            uv add --editable --workspace "./$repo_name/$parent_dir"
        done <<< "$pkg_parents"

        echo "✓ Cloned: $repo_name"
    done < <(jq -r '.["dev-repos"] | keys[]' "$ws_root/.workspace_info.json")

# Spawn an agent session using the prompt from .workspace_info.json
[group('workspace')]
spawn-agent:
    #!/usr/bin/env bash
    set -eo pipefail
    ws_root="{{ ws_root }}"
    prompt=$(jq -r '.prompt // empty' "$ws_root/.workspace_info.json")
    pgid=$(ps -o pgid= -p $$ | tr -d ' ')
    jq --arg pgid "$pgid" '.agent = {"pgid": ($pgid | tonumber)}' \
        "$ws_root/.workspace_info.json" > "$ws_root/.workspace_info.json.tmp" \
        && mv "$ws_root/.workspace_info.json.tmp" "$ws_root/.workspace_info.json"
    exec kiro-cli chat --agent dlq -a "$prompt"

# Stop the agent session
[group('workspace')]
stop-agent:
    #!/usr/bin/env bash
    set -eo pipefail
    ws_root="{{ ws_root }}"

    agent_pgid=$(jq -r '.agent.pgid // empty' "$ws_root/.workspace_info.json")
    if [[ -z "$agent_pgid" ]]; then
        echo "Error: no agent is running in this workspace." >&2
        exit 1
    fi

    echo "Stopping agent..."
    kill -TERM -- -"$agent_pgid" 2>/dev/null || true

    for i in {1..12}; do
        if ! kill -0 -- -"$agent_pgid" 2>/dev/null; then
            jq '.agent = null' "$ws_root/.workspace_info.json" > "$ws_root/.workspace_info.json.tmp" \
                && mv "$ws_root/.workspace_info.json.tmp" "$ws_root/.workspace_info.json"
            echo "✓ Agent stopped"
            exit 0
        fi
        sleep 0.25
    done

    echo "Agent didn't stop within 3s, force killing..."
    kill -9 -- -"$agent_pgid" 2>/dev/null || true
    jq '.agent = null' "$ws_root/.workspace_info.json" > "$ws_root/.workspace_info.json.tmp" \
        && mv "$ws_root/.workspace_info.json.tmp" "$ws_root/.workspace_info.json"
    echo "✓ Agent force killed"

# Close this workspace (stop agent + server, close cmux workspace)
[group('workspace')]
close-workspace:
    #!/usr/bin/env bash
    set -eo pipefail
    ws_root="{{ ws_root }}"

    # Stop agent if running
    agent_pgid=$(jq -r '.agent.pgid // empty' "$ws_root/.workspace_info.json")
    if [[ -n "$agent_pgid" ]] && kill -0 -- -"$agent_pgid" 2>/dev/null; then
        just stop-agent
    fi

    # Stop server if running
    server_pgid=$(jq -r '.server.pgid // empty' "$ws_root/.workspace_info.json")
    if [[ -n "$server_pgid" ]] && kill -0 -- -"$server_pgid" 2>/dev/null; then
        just stop-server
    fi

    cmux close-workspace --workspace "${CMUX_WORKSPACE_ID}"

################################################################################
# Server recipes
################################################################################

# Check if a server is running in this workspace
[group('workspace-server')]
server-status:
    @jq -r '.server.url // empty' "{{ ws_root }}/.workspace_info.json"

# Start JupyterLab in a new tab
[group('workspace-server')]
start-server *args:
    #!/usr/bin/env bash
    set -eo pipefail
    ws_root="{{ ws_root }}"

    # Check if server already running
    existing=$(jq -r '.server.url // empty' "$ws_root/.workspace_info.json")
    if [[ -n "$existing" ]]; then
        echo "Error: a Jupyter server is already running at $existing" >&2
        echo "Use 'just restart-server' to restart it." >&2
        exit 1
    fi

    # Get current pane
    pane=$(cmux identify --json | jq -r '.caller.pane_ref')

    # Start server in a new terminal tab (same pane, no browser)
    surface_json=$(cmux new-surface --workspace "${CMUX_WORKSPACE_ID}" --pane "$pane" --type terminal --focus false --json)
    server_surface=$(echo "$surface_json" | jq -r '.surface_ref')

    cmux send --workspace "${CMUX_WORKSPACE_ID}" --surface "$server_surface" "cd $ws_root && CLAUDE_CODE_USE_BEDROCK=1 uv run jupyter lab --no-browser --expose-app-in-browser --config=./jupyter_server_config.py {{ args }}\n" > /dev/null

    # Wait for server to start
    echo "Waiting for server to start..."
    for i in {1..30}; do
        sleep 1
        server_json=$(uv run jupyter server list --jsonlist 2>/dev/null | jq --arg root "$ws_root" '[.[] | select(.root_dir == $root)] | .[0] // empty')
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

    # Save server info (including PID and PGID)
    pid=$(echo "$server_json" | jq -r '.pid')
    pgid=$(ps -o pgid= -p "$pid" | tr -d ' ')
    jq --arg sid "$server_surface" --arg url "$url" --arg token "$token" --arg pid "$pid" --arg pgid "$pgid" \
        '.server = {"surface_id": $sid, "url": $url, "token": $token, "pid": ($pid | tonumber), "pgid": ($pgid | tonumber)}' \
        "$ws_root/.workspace_info.json" > "$ws_root/.workspace_info.json.tmp" \
        && mv "$ws_root/.workspace_info.json.tmp" "$ws_root/.workspace_info.json"

    echo "✓ JupyterLab running at ${url}lab?token=${token}"
    echo "  Server surface: $server_surface"
    echo "  PGID: $pgid"

# Stop the JupyterLab server
[group('workspace-server')]
stop-server:
    #!/usr/bin/env bash
    set -eo pipefail
    ws_root="{{ ws_root }}"

    # Read server info
    server_pgid=$(jq -r '.server.pgid // empty' "$ws_root/.workspace_info.json")
    server_surface=$(jq -r '.server.surface_id // empty' "$ws_root/.workspace_info.json")

    if [[ -z "$server_pgid" ]]; then
        echo "Error: no server is running in this workspace." >&2
        exit 1
    fi

    # Kill the process group gracefully
    echo "Stopping server..."
    kill -TERM -- -"$server_pgid" 2>/dev/null || true

    # Poll every 250ms for up to 3s
    for i in {1..12}; do
        if ! kill -0 -- -"$server_pgid" 2>/dev/null; then
            # Close the server terminal surface
            [[ -n "$server_surface" ]] && cmux close-surface --surface "$server_surface" > /dev/null 2>/dev/null || true
            jq '.server = null' "$ws_root/.workspace_info.json" > "$ws_root/.workspace_info.json.tmp" \
                && mv "$ws_root/.workspace_info.json.tmp" "$ws_root/.workspace_info.json"
            echo "✓ Server stopped"
            exit 0
        fi
        sleep 0.25
    done

    # Force kill
    echo "Server didn't stop gracefully within 3s, force killing..."
    kill -9 -- -"$server_pgid" 2>/dev/null || true
    # Close the server terminal surface
    [[ -n "$server_surface" ]] && cmux close-surface --surface "$server_surface" > /dev/null 2>/dev/null || true
    jq '.server = null' "$ws_root/.workspace_info.json" > "$ws_root/.workspace_info.json.tmp" \
        && mv "$ws_root/.workspace_info.json.tmp" "$ws_root/.workspace_info.json"
    echo "✓ Server force killed"

# Restart the JupyterLab server
[group('workspace-server')]
restart-server:
    just stop-server
    just start-server

# Print the browser surface ref in the current workspace
[group('workspace-browser')]
get-browser-surface:
    @jq -r '.browser.surface_id // empty' "{{ ws_root }}/.workspace_info.json"

################################################################################
# Browser recipes
################################################################################

# Open a browser to JupyterLab in the current workspace
[group('workspace-browser')]
open-browser:
    #!/usr/bin/env bash
    set -eo pipefail
    ws_root="{{ ws_root }}"

    # Check if browser already open
    existing=$(jq -r '.browser.surface_id // empty' "$ws_root/.workspace_info.json")
    if [[ -n "$existing" ]]; then
        echo "Error: A browser is already open. Use 'just refresh-browser' or 'just close-browser' first." >&2
        exit 1
    fi

    # Require a running server
    url=$(jq -r '.server.url // empty' "$ws_root/.workspace_info.json")
    token=$(jq -r '.server.token // empty' "$ws_root/.workspace_info.json")
    if [[ -z "$url" || -z "$token" ]]; then
        echo "Error: no server is running. Use 'just start-server' first." >&2
        exit 1
    fi

    # Open browser
    browser_json=$(cmux --json browser open "${url}lab?token=${token}" --workspace "${CMUX_WORKSPACE_ID}")
    browser_surface=$(echo "$browser_json" | jq -r '.surface_ref')
    jq --arg sid "$browser_surface" '.browser = {"surface_id": $sid}' \
        "$ws_root/.workspace_info.json" > "$ws_root/.workspace_info.json.tmp" \
        && mv "$ws_root/.workspace_info.json.tmp" "$ws_root/.workspace_info.json"

    echo "✓ Browser opened: $browser_surface"

# Reload the browser in the current workspace
[group('workspace-browser')]
refresh-browser:
    #!/usr/bin/env bash
    set -eo pipefail
    ws_root="{{ ws_root }}"
    surface=$(jq -r '.browser.surface_id // empty' "$ws_root/.workspace_info.json")
    if [[ -z "$surface" ]]; then
        echo "Error: no browser is open. Use 'just open-browser' first." >&2
        exit 1
    fi
    cmux browser "$surface" reload > /dev/null
    echo "✓ Browser reloaded"

# Close the browser in the current workspace
[group('workspace-browser')]
close-browser:
    #!/usr/bin/env bash
    set -eo pipefail
    ws_root="{{ ws_root }}"
    surface=$(jq -r '.browser.surface_id // empty' "$ws_root/.workspace_info.json")
    if [[ -z "$surface" ]]; then
        echo "Error: no browser is open." >&2
        exit 1
    fi
    cmux close-surface --surface "$surface" > /dev/null
    jq '.browser = null' "$ws_root/.workspace_info.json" > "$ws_root/.workspace_info.json.tmp" \
        && mv "$ws_root/.workspace_info.json.tmp" "$ws_root/.workspace_info.json"
    echo "✓ Browser closed"

################################################################################
# Top-level aliases
################################################################################

# Start server and open browser
[group('workspace')]
start: start-server open-browser

# Restart server and refresh browser
[group('workspace')]
restart: restart-server refresh-browser

################################################################################
# Chat recipes
################################################################################

# Open a new chat (side panel by default, --mainarea for main area)
[group('workspace-chat')]
open-chat *args:
    #!/usr/bin/env bash
    set -eo pipefail
    ws_root="{{ ws_root }}"
    surface=$(jq -r '.browser.surface_id // empty' "$ws_root/.workspace_info.json")
    if [[ -z "$surface" ]]; then
        echo "Error: no browser is open. Use 'just open-browser' first." >&2
        exit 1
    fi

    chat_name="chat-$(date +%s)"
    mainarea=false
    for arg in {{ args }}; do
        if [[ "$arg" == "--mainarea" ]]; then
            mainarea=true
        fi
    done

    if [[ "$mainarea" == "true" ]]; then
        # Open a new launcher tab, then click the Chat card
        cmux browser "$surface" eval "window.jupyterapp.commands.execute('launcher:create')"
        sleep 1
        cmux browser "$surface" click --text "Chat"
        sleep 0.5
        # Fill the chat name dialog and confirm
        cmux browser "$surface" fill --ref "$(cmux browser "$surface" snapshot --interactive | grep -i 'name' | head -1 | awk '{print $1}')" "$chat_name"
        cmux browser "$surface" click --text "Ok"
    else
        # Open/focus the Jupyter Chat side panel
        cmux browser "$surface" eval "window.jupyterapp.commands.execute('jupyter-chat:open')"
        sleep 1
        # Click "+" to create a new chat
        cmux browser "$surface" click --ref "$(cmux browser "$surface" snapshot --interactive | grep -E '^\S+.*button.*\+' | head -1 | awk '{print $1}')" 2>/dev/null \
            || cmux browser "$surface" click --text "+"
        sleep 0.5
        # Fill the chat name dialog and confirm
        cmux browser "$surface" fill --ref "$(cmux browser "$surface" snapshot --interactive | grep -i 'name' | head -1 | awk '{print $1}')" "$chat_name"
        cmux browser "$surface" click --text "Ok"
    fi

    echo "✓ Chat opened: $chat_name"

# Send a message to the currently active chat
[group('workspace-chat')]
[arg("message", help="message to send")]
send-chat-message message:
    #!/usr/bin/env bash
    set -eo pipefail
    ws_root="{{ ws_root }}"
    surface=$(jq -r '.browser.surface_id // empty' "$ws_root/.workspace_info.json")
    if [[ -z "$surface" ]]; then
        echo "Error: no browser is open. Use 'just open-browser' first." >&2
        exit 1
    fi

    # Find and fill the chat input, then send
    cmux browser "$surface" click --role "combobox"
    cmux browser "$surface" fill --role "combobox" "{{ message }}"
    cmux browser "$surface" press --role "combobox" "Enter"
    echo "✓ Message sent"
