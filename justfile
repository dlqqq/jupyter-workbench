set dotenv-load := true

helpers := justfile_directory() / "scripts/helpers.sh"
invocation := invocation_directory()

################################################################################
# Workbench recipes (can be run anywhere within the workbench)
################################################################################

# Create a new worktree: just worktree-add <name> [--dev] <repos...> [--with <packages...>]
[group('workbench')]
worktree-add *args:
    #!/usr/bin/env bash
    set -eo pipefail
    source "{{ helpers }}"
    get_workbench_root "$PWD" || exit 1
    cd "$WB_ROOT"

    # Parse arguments
    name=""
    dev_repos=()
    with_pkgs=()
    mode="dev"

    for arg in {{ args }}; do
        case "$arg" in
            --dev)  mode="dev"; continue ;;
            --with) mode="with"; continue ;;
        esac
        if [[ -z "$name" ]]; then
            name="$arg"
        elif [[ "$mode" == "dev" ]]; then
            dev_repos+=("$arg")
        else
            with_pkgs+=("$arg")
        fi
    done

    if [[ -z "$name" ]]; then
        echo "Usage: just worktree-add <name> [--dev <repos...>] [--with <packages...>]" >&2
        exit 1
    fi

    # Validate dev repo names
    for repo in "${dev_repos[@]}"; do
        url=$(jq -r --arg r "$repo" '.[$r].url // empty' "$WB_ROOT/repos.json")
        if [[ -z "$url" ]]; then
            echo "Error: '$repo' not found in repos.json" >&2
            echo "Available repos: $(jq -r 'keys[]' "$WB_ROOT/repos.json" | tr '\n' ' ')" >&2
            exit 1
        fi
    done

    wt="$WB_ROOT/worktrees/$name"
    if [[ -d "$wt" ]]; then
        echo "Error: worktree '$name' already exists at $wt" >&2
        exit 1
    fi

    # Create worktree (detached)
    mkdir -p "$WB_ROOT/worktrees"
    git worktree add --detach "$wt"

    # Copy latest justfile, scripts, and .env into worktree
    cp "$WB_ROOT/justfile" "$wt/justfile"
    rm -rf "$wt/scripts"
    cp -r "$WB_ROOT/scripts" "$wt/scripts"
    [[ -f "$WB_ROOT/.env" ]] && cp "$WB_ROOT/.env" "$wt/.env"

    # Write worktree info
    if [[ ${#dev_repos[@]} -gt 0 ]]; then
        repos_json=$(printf '%s\n' "${dev_repos[@]}" | jq -R . | jq -s .)
    else
        repos_json="[]"
    fi
    jq -n --argjson repos "$repos_json" \
        '{"dev-repos": $repos, "workspace_id": "", "server": null, "browser": null}' \
        > "$wt/.worktree_info.json"

    cd "$wt"

    # Clone and dev-install repos
    for repo in "${dev_repos[@]}"; do
        url=$(jq -r --arg r "$repo" '.[$r].url' "$WB_ROOT/repos.json")
        echo "Cloning $repo..."
        git clone "$url" "$repo"

        # Get package parent dirs from repos.json (default: ".")
        pkg_parents=$(jq -r --arg r "$repo" '
            .[$r].packages // [{"parentDir": "."}]
            | .[].parentDir
        ' "$WB_ROOT/repos.json")

        while IFS= read -r parent_dir; do
            uv add --editable --workspace "./$repo/$parent_dir"
        done <<< "$pkg_parents"
    done

    # Install --with packages from PyPI
    if [[ ${#with_pkgs[@]} -gt 0 ]]; then
        echo "Adding PyPI packages: ${with_pkgs[*]}"
        uv add "${with_pkgs[@]}"
    fi

    # Enable extensions
    if [[ ${#dev_repos[@]} -gt 0 ]]; then
        just "$wt/enable-all-extensions"
    fi

    # Sync
    just "$wt/sync"

    echo ""
    echo "✓ Worktree '$name' ready at: $wt"
    echo "  cd $wt && just server-start"

# Remove a worktree
[group('workbench')]
worktree-remove name:
    #!/usr/bin/env bash
    set -eo pipefail
    source "{{ helpers }}"
    get_workbench_root "$PWD" || exit 1
    wt="$WB_ROOT/worktrees/{{ name }}"
    if [[ ! -d "$wt" ]]; then
        echo "Error: worktree '{{ name }}' not found" >&2
        exit 1
    fi
    cd "$WB_ROOT"
    git worktree remove "$wt" --force
    echo "✓ Removed worktree '{{ name }}'"

# Remove all worktrees and start fresh
[group('workbench')]
worktree-remove-all:
    #!/usr/bin/env bash
    set -eo pipefail
    source "{{ helpers }}"
    get_workbench_root "$PWD" || exit 1
    cd "$WB_ROOT"
    for wt in worktrees/*/; do
        [[ -d "$wt" ]] || continue
        name=$(basename "$wt")
        echo "Removing $name..."
        git worktree remove "$wt" --force
    done
    rm -rf worktrees
    echo "✓ All worktrees removed"

# Sync justfile, scripts, and skills to all worktrees
[group('workbench')]
sync-workbench:
    #!/usr/bin/env bash
    set -eo pipefail
    source "{{ helpers }}"
    get_workbench_root "$PWD" || exit 1
    for wt in "$WB_ROOT"/worktrees/*/; do
        [[ -d "$wt" ]] || continue
        name=$(basename "$wt")
        cp "$WB_ROOT/justfile" "$wt/justfile"
        rm -rf "$wt/scripts"
        cp -r "$WB_ROOT/scripts" "$wt/scripts"
        rm -rf "$wt/.kiro/skills"
        mkdir -p "$wt/.kiro"
        cp -r "$WB_ROOT/.kiro/skills" "$wt/.kiro/skills"
        echo "✓ $name"
    done

################################################################################
# Worktree recipes (can be run anywhere within a worktree)
################################################################################

# Add a package via uv (same as 'uv add')
[group('worktree')]
add +pkgs:
    #!/usr/bin/env bash
    set -eo pipefail
    source "{{ helpers }}"
    get_worktree_root "$PWD" || exit 1

    uv add {{ pkgs }}

# Add a package as editable (clone, build, dev-install)
[group('worktree')]
add-dev repo:
    #!/usr/bin/env bash
    set -eo pipefail
    source "{{ helpers }}"
    get_worktree_root "$PWD" || exit 1
    get_workbench_root "$PWD" || exit 1
    cd "$WT_ROOT"

    repo="{{ repo }}"
    url=$(jq -r --arg r "$repo" '.[$r].url // empty' "$WB_ROOT/repos.json")
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

    pkg_parents=$(jq -r --arg r "$repo" '
        .[$r].packages // [{"parentDir": "."}]
        | .[].parentDir
    ' "$WB_ROOT/repos.json")

    while IFS= read -r parent_dir; do
        uv add --editable --workspace "./$repo/$parent_dir"
    done <<< "$pkg_parents"

    # Update .worktree_info.json
    jq --arg repo "$repo" '.["dev-repos"] += [$repo]' "$WT_ROOT/.worktree_info.json" > "$WT_ROOT/.worktree_info.json.tmp" \
        && mv "$WT_ROOT/.worktree_info.json.tmp" "$WT_ROOT/.worktree_info.json"

    # Enable extensions
    cd "$repo"
    just enable-repo-extensions

    echo ""
    echo "✓ Added: $repo"

# Alias for `uv sync`
[group('worktree')]
sync *args:
    #!/usr/bin/env bash
    set -eo pipefail
    source "{{ helpers }}"
    get_worktree_root "$PWD" || exit 1
    uv sync

# Start JupyterLab in a new tab and open browser to the right
[group('worktree')]
server-start *args:
    #!/usr/bin/env bash
    set -eo pipefail
    source "{{ helpers }}"
    get_worktree_root "$PWD" || exit 1
    check_no_server_running || exit 1

    # Get current pane
    pane=$(cmux identify --json | jq -r '.caller.pane_ref')

    # Start server in a new terminal tab (same pane, no browser)
    surface_json=$(cmux new-surface --workspace "${CMUX_WORKSPACE_ID}" --pane "$pane" --type terminal --focus false --json)
    server_surface=$(echo "$surface_json" | jq -r '.surface_ref')

    cmux send --workspace "${CMUX_WORKSPACE_ID}" --surface "$server_surface" "cd $WT_ROOT && uv run jupyter lab --no-browser --expose-app-in-browser --config=./jupyter_server_config.py {{ args }}\n"

    # Wait for server to start
    echo "Waiting for server to start..."
    for i in {1..30}; do
        sleep 1
        server_json=$(uv run jupyter server list --jsonlist 2>/dev/null | jq --arg root "$WT_ROOT" '[.[] | select(.root_dir == $root)] | .[0] // empty')
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
    set_server_info "$server_surface" "$url" "$token" "$pid" "$pgid"

    # Open browser with token
    browser_json=$(cmux --json browser open "${url}lab?token=${token}" --workspace "${CMUX_WORKSPACE_ID}")
    browser_surface=$(echo "$browser_json" | jq -r '.surface_ref')
    set_browser_info "$browser_surface"

    echo "✓ JupyterLab running at ${url}lab?token=${token}"
    echo "  Server surface: $server_surface"
    echo "  Browser surface: $browser_surface"
    echo "  PGID: $pgid"

# Stop the JupyterLab server
[group('worktree')]
server-stop:
    #!/usr/bin/env bash
    set -eo pipefail
    source "{{ helpers }}"
    get_worktree_root "$PWD" || exit 1

    # Read server info
    server_pgid=$(jq -r '.server.pgid // empty' "$WT_ROOT/.worktree_info.json")

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
            clear_server_info
            echo "✓ Server stopped"
            exit 0
        fi
        sleep 0.25
    done

    # Force kill
    echo "Server didn't stop gracefully within 3s, force killing..."
    kill -9 -- -"$server_pgid" 2>/dev/null || true
    clear_server_info
    echo "✓ Server force killed"

# Restart the JupyterLab server
[group('worktree')]
server-restart:
    just server-stop
    just server-start

# Print the browser surface ref in the current workspace
[group('worktree')]
get-browser-surface:
    #!/usr/bin/env bash
    set -eo pipefail
    for pane in $(cmux list-panes --workspace "${CMUX_WORKSPACE_ID}" --json | jq -r '.panes[].ref'); do
        ref=$(cmux list-pane-surfaces --workspace "${CMUX_WORKSPACE_ID}" --pane "$pane" --json | jq -r '.surfaces[] | select(.type == "browser") | .ref')
        if [[ -n "$ref" ]]; then
            echo "$ref"
            exit 0
        fi
    done
    echo "Error: no browser surface found in this workspace" >&2
    exit 1

# Show which packages are dev-installed in this worktree
[group('worktree')]
worktree-status:
    #!/usr/bin/env bash
    set -eo pipefail
    source "{{ helpers }}"
    get_worktree_root "$PWD" || exit 1
    echo "Dev-installed packages:"
    grep 'editable = true' "pyproject.toml" | cut -d= -f1 | sed 's/^/  /'

# Enable extensions for all dev-installed repos in this worktree
[group('worktree')]
enable-all-extensions:
    #!/usr/bin/env bash
    set -eo pipefail
    source "{{ helpers }}"
    get_worktree_root "$PWD" || exit 1
    get_worktree_repos
    for repo in "${WT_REPOS[@]}"; do
        echo "=== $repo ==="
        (cd $repo && just enable-repo-extensions)
    done

# Build all dev-installed repos in this worktree
[group('worktree')]
build-all:
    #!/usr/bin/env bash
    set -eo pipefail
    source "{{ helpers }}"
    get_worktree_root "$PWD" || exit 1
    get_worktree_repos
    for repo in "${WT_REPOS[@]}"; do
        echo "=== $repo ==="
        (cd $repo && just build)
    done

################################################################################
# Repo recipes (can only be run from inside a repo within a worktree)
#
# These use [no-cd] so they can run from the invocation directory, rather than
# the default justfile_directory() (i.e. the worktree root). This allows repo
# recipes to be invoked simply via `(cd $repo && just <repo-recipe>)` in other
# higher-level recipes.
################################################################################

# Run `jlpm` (JupyterLab's bundled version of `yarn`), forwarding given arguments
[group('repo')]
[no-cd]
jlpm *args:
    #!/usr/bin/env bash
    set -eo pipefail
    source "{{ helpers }}"
    get_worktree_repo "{{ invocation }}" || exit 1
    uv run --project "$WT_ROOT" jlpm {{ args }}

# Run `pytest` on a repo, forwarding given arguments
[group('repo')]
[no-cd]
pytest *args:
    #!/usr/bin/env bash
    set -eo pipefail
    source "{{ helpers }}"
    get_worktree_repo "{{ invocation }}" || exit 1
    uv run --project "$WT_ROOT" pytest {{ args }}

# Run `mypy` on a repo, forwarding given arguments
[group('repo')]
[no-cd]
mypy *args:
    #!/usr/bin/env bash
    set -eo pipefail
    source "{{ helpers }}"
    get_worktree_repo "{{ invocation }}" || exit 1
    uv run --project "$WT_ROOT" mypy {{ args }}

# Run frontend linters
[group('repo')]
[no-cd]
lint:
    #!/usr/bin/env bash
    set -eo pipefail
    source "{{ helpers }}"
    get_worktree_repo "{{ invocation }}" || exit 1
    # run twice because linters occasionally require 2 runs
    uv run --project "$WT_ROOT" jlpm lint
    uv run --project "$WT_ROOT" jlpm lint

# Rebuild frontend for the current repo
[group('repo')]
[no-cd]
build:
    #!/usr/bin/env bash
    set -eo pipefail
    source "{{ helpers }}"
    get_worktree_repo "{{ invocation }}" || exit 1
    uv run --project "$WT_ROOT" jlpm build

# Enable all extensions for this repo
[group('repo')]
[no-cd]
enable-repo-extensions:
    #!/usr/bin/env bash
    set -eo pipefail
    source "{{ helpers }}"
    get_worktree_repo "{{ invocation }}" || exit 1
    just enable-repo-server-extensions
    just enable-repo-lab-extensions

# Enable server extension(s) for this repo
[group('repo')]
[no-cd]
enable-repo-server-extensions:
    #!/usr/bin/env bash
    set -eo pipefail
    source "{{ helpers }}"
    get_worktree_repo "{{ invocation }}" || exit 1
    get_workbench_root "{{ invocation }}" || exit 1
    get_repo_pkg_names
    cd "$WT_ROOT"
    for pkg_name in "${PKG_NAMES[@]}"; do
        echo "Enabling server extension: $pkg_name"
        uv run jupyter server extension enable "$pkg_name"
    done

# Enable lab extension(s) for this repo
[group('repo')]
[no-cd]
enable-repo-lab-extensions:
    #!/usr/bin/env bash
    set -eo pipefail
    source "{{ helpers }}"
    get_worktree_repo "{{ invocation }}" || exit 1
    get_workbench_root "{{ invocation }}" || exit 1
    get_repo_pkg_parents
    cd "$REPO_ROOT"
    for parent_dir in "${PKG_PARENT_DIRS[@]}"; do
        echo "Enabling lab extension in: $REPO_NAME/$parent_dir"
        (cd "$parent_dir" && uv run --project "$WT_ROOT" jupyter labextension develop . --overwrite) || true
    done

# Ensure a fork exists and is set as a remote
[group('repo')]
[no-cd]
ensure-fork:
    #!/usr/bin/env bash
    set -eo pipefail
    source "{{ helpers }}"
    get_worktree_repo "{{ invocation }}" || exit 1
    cd "$REPO_ROOT"
    if ! git remote get-url fork &>/dev/null; then
        echo "Forking..."
        gh repo fork --remote --remote-name fork
        gh repo set-default "$(git remote get-url origin | sed 's|.*github.com[:/]||;s|\.git$||')"
    else
        echo "Fork remote already exists"
    fi
