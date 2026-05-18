set dotenv-load := true
set fallback

wt_root := justfile_directory()

# Echo the worktree root directory
[group('worktree')]
get-worktree-root:
    @echo "{{ wt_root }}"

# List all available recipes (including workbench)
[group('worktree')]
list-recipes:
    #!/usr/bin/env bash
    (cd "$(just get-workbench-root)" && just --list --list-prefix="")
    echo ""
    just --list --list-prefix=""

# Add a package via uv (same as 'uv add')
[group('worktree')]
add +pkgs:
    uv add {{ pkgs }}

# Add a package as editable (clone, build, dev-install)
[group('worktree')]
add-dev repo:
    #!/usr/bin/env bash
    set -eo pipefail
    wt_root="{{ wt_root }}"
    wb_root=$(just get-workbench-root)
    cd "$wt_root"

    repo="{{ repo }}"
    url=$(jq -r --arg r "$repo" '.[$r].url // empty' "$wt_root/repos.json")
    if [[ -z "$url" ]]; then
        echo "Error: '$repo' not found in repos.json" >&2
        exit 1
    fi
    if [[ -d "$repo" ]]; then
        echo "Error: '$repo' already exists in this worktree" >&2
        exit 1
    fi

    # Clone and add as editable workspace member
    echo "Cloning $repo..."
    git clone "$url" "$repo"

    # Copy repo justfile and exclude from git
    cp "$wb_root/repo.just" "$repo/justfile"
    grep -qxF 'justfile' "$repo/.git/info/exclude" 2>/dev/null || echo 'justfile' >> "$repo/.git/info/exclude"

    pkg_parents=$(jq -r --arg r "$repo" '
        .[$r].packages // [{"parentDir": "."}]
        | .[].parentDir
    ' "$wt_root/repos.json")

    while IFS= read -r parent_dir; do
        uv add --editable --workspace "./$repo/$parent_dir"
    done <<< "$pkg_parents"

    # Update .worktree_info.json
    jq --arg repo "$repo" '.["dev-repos"] += [$repo]' "$wt_root/.worktree_info.json" > "$wt_root/.worktree_info.json.tmp" \
        && mv "$wt_root/.worktree_info.json.tmp" "$wt_root/.worktree_info.json"

    # Enable extensions
    cd "$repo"
    just enable-repo-extensions

    echo ""
    echo "✓ Added: $repo"

# Alias for `uv sync`
[group('worktree')]
sync *args:
    uv sync

# Show which packages are dev-installed in this worktree
[group('worktree')]
worktree-status:
    #!/usr/bin/env bash
    set -eo pipefail
    echo "Dev-installed repos:"
    jq -r '.["dev-repos"][]' "{{ wt_root }}/.worktree_info.json"

# Enable extensions for all dev-installed repos in this worktree
[group('worktree')]
enable-all-extensions:
    #!/usr/bin/env bash
    set -eo pipefail
    wt_root="{{ wt_root }}"
    repos=$(jq -r '.["dev-repos"][]' "$wt_root/.worktree_info.json")
    while IFS= read -r repo; do
        [[ -n "$repo" ]] || continue
        echo "=== $repo ==="
        (cd "$wt_root/$repo" && just enable-repo-extensions)
    done <<< "$repos"

# Build all dev-installed repos in this worktree
[group('worktree')]
build-all:
    #!/usr/bin/env bash
    set -eo pipefail
    wt_root="{{ wt_root }}"
    repos=$(jq -r '.["dev-repos"][]' "$wt_root/.worktree_info.json")
    while IFS= read -r repo; do
        [[ -n "$repo" ]] || continue
        echo "=== $repo ==="
        (cd "$wt_root/$repo" && just build)
    done <<< "$repos"

################################################################################
# Server recipes
################################################################################

# Check if a server is running in this worktree
[group('worktree-server')]
server-status:
    @jq -r '.server.url // empty' "{{ wt_root }}/.worktree_info.json"

# Start JupyterLab in a new tab and open browser to the right
[group('worktree-server')]
server-start *args:
    #!/usr/bin/env bash
    set -eo pipefail
    wt_root="{{ wt_root }}"

    # Check if server already running
    existing=$(jq -r '.server.url // empty' "$wt_root/.worktree_info.json")
    if [[ -n "$existing" ]]; then
        echo "Error: a Jupyter server is already running at $existing" >&2
        echo "Use 'just server-restart' to restart it." >&2
        exit 1
    fi

    # Get current pane
    pane=$(cmux identify --json | jq -r '.caller.pane_ref')

    # Start server in a new terminal tab (same pane, no browser)
    surface_json=$(cmux new-surface --workspace "${CMUX_WORKSPACE_ID}" --pane "$pane" --type terminal --focus false --json)
    server_surface=$(echo "$surface_json" | jq -r '.surface_ref')

    cmux send --workspace "${CMUX_WORKSPACE_ID}" --surface "$server_surface" "cd $wt_root && uv run jupyter lab --no-browser --expose-app-in-browser --config=./jupyter_server_config.py {{ args }}\n"

    # Wait for server to start
    echo "Waiting for server to start..."
    for i in {1..30}; do
        sleep 1
        server_json=$(uv run jupyter server list --jsonlist 2>/dev/null | jq --arg root "$wt_root" '[.[] | select(.root_dir == $root)] | .[0] // empty')
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
        "$wt_root/.worktree_info.json" > "$wt_root/.worktree_info.json.tmp" \
        && mv "$wt_root/.worktree_info.json.tmp" "$wt_root/.worktree_info.json"

    # Open browser with token
    browser_json=$(cmux --json browser open "${url}lab?token=${token}" --workspace "${CMUX_WORKSPACE_ID}")
    browser_surface=$(echo "$browser_json" | jq -r '.surface_ref')
    jq --arg sid "$browser_surface" \
        '.browser = {"surface_id": $sid}' \
        "$wt_root/.worktree_info.json" > "$wt_root/.worktree_info.json.tmp" \
        && mv "$wt_root/.worktree_info.json.tmp" "$wt_root/.worktree_info.json"

    echo "✓ JupyterLab running at ${url}lab?token=${token}"
    echo "  Server surface: $server_surface"
    echo "  Browser surface: $browser_surface"
    echo "  PGID: $pgid"

# Stop the JupyterLab server
[group('worktree-server')]
server-stop:
    #!/usr/bin/env bash
    set -eo pipefail
    wt_root="{{ wt_root }}"

    # Read server info
    server_pgid=$(jq -r '.server.pgid // empty' "$wt_root/.worktree_info.json")

    if [[ -z "$server_pgid" ]]; then
        echo "Error: no server is running in this workspace." >&2
        exit 1
    fi

    # Kill the process group gracefully
    echo "Stopping server (PGID $server_pgid): kill -TERM -- -$server_pgid"
    kill -TERM -- -"$server_pgid" 2>/dev/null || true

    # Poll every 250ms for up to 3s
    for i in {1..12}; do
        if ! kill -0 -- -"$server_pgid" 2>/dev/null; then
            jq '.server = null | .browser = null' "$wt_root/.worktree_info.json" > "$wt_root/.worktree_info.json.tmp" \
                && mv "$wt_root/.worktree_info.json.tmp" "$wt_root/.worktree_info.json"
            echo "✓ Server stopped"
            exit 0
        fi
        sleep 0.25
    done

    # Force kill
    echo "Server didn't stop gracefully within 3s, force killing..."
    kill -9 -- -"$server_pgid" 2>/dev/null || true
    jq '.server = null | .browser = null' "$wt_root/.worktree_info.json" > "$wt_root/.worktree_info.json.tmp" \
        && mv "$wt_root/.worktree_info.json.tmp" "$wt_root/.worktree_info.json"
    echo "✓ Server force killed"

# Restart the JupyterLab server
[group('worktree-server')]
server-restart:
    just server-stop
    just server-start

# Print the browser surface ref in the current workspace
[group('worktree-server')]
get-browser-surface:
    @jq -r '.browser.surface_id // empty' "{{ wt_root }}/.worktree_info.json"
