set dotenv-load := true

# Echo the workbench root directory
[group('workbench')]
get-workbench-root:
    @echo "{{ justfile_directory() }}"

# List all available recipes
[group('workbench')]
list-recipes:
    @just --list --list-heading=""

# Create a new workspace: just workspace-add <name> [--dev] <repos...> [--with <packages...>]
[group('workbench')]
workspace-add *args:
    #!/usr/bin/env bash
    set -eo pipefail
    wb_root="{{ justfile_directory() }}"
    cd "$wb_root"

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
        echo "Usage: just workspace-add <name> [--dev <repos...>] [--with <packages...>]" >&2
        exit 1
    fi

    # Validate dev repo names
    for repo in "${dev_repos[@]}"; do
        url=$(jq -r --arg r "$repo" '.[$r].url // empty' "$wb_root/repos.json")
        if [[ -z "$url" ]]; then
            echo "Error: '$repo' not found in repos.json" >&2
            echo "Available repos: $(jq -r 'keys[]' "$wb_root/repos.json" | tr '\n' ' ')" >&2
            exit 1
        fi
    done

    ws="$wb_root/workspaces/$name"
    if [[ -d "$ws" ]]; then
        echo "Error: workspace '$name' already exists at $ws" >&2
        exit 1
    fi

    # Create workspace directory
    mkdir -p "$ws"
    cp "$wb_root/template/"* "$ws/"

    # Symlink workspace justfile and skills to workbench root
    ln -sf "$wb_root/workspace.just" "$ws/justfile"
    mkdir -p "$ws/.kiro"
    ln -sf "$wb_root/.kiro/skills" "$ws/.kiro/skills"
    [[ -f "$wb_root/.env" ]] && cp "$wb_root/.env" "$ws/.env"

    cd "$ws"

    # Write workspace info
    if [[ ${#dev_repos[@]} -gt 0 ]]; then
        repos_json=$(printf '%s\n' "${dev_repos[@]}" | jq -R . | jq -s .)
    else
        repos_json="[]"
    fi
    jq -n --argjson repos "$repos_json" \
        '{"dev-repos": $repos, "workspace_id": "", "server": null, "browser": null}' \
        > "$ws/.workspace_info.json"

    cd "$ws"

    # Clone and dev-install repos
    for repo in "${dev_repos[@]}"; do
        url=$(jq -r --arg r "$repo" '.[$r].url' "$wb_root/repos.json")
        echo "Cloning $repo..."
        git clone "$url" "$repo"

        # Symlink repo justfile and exclude it from git
        ln -sf "$wb_root/repo.just" "$repo/justfile"
        grep -qxF 'justfile' "$repo/.git/info/exclude" 2>/dev/null || echo 'justfile' >> "$repo/.git/info/exclude"

        # Get package parent dirs from repos.json (default: ".")
        pkg_parents=$(jq -r --arg r "$repo" '
            .[$r].packages // [{"parentDir": "."}]
            | .[].parentDir
        ' "$wb_root/repos.json")

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
        just enable-all-extensions
    fi

    # Sync
    just sync

    echo ""
    echo "✓ Worktree '$name' ready at: $ws"
    echo "  cd $ws && just server-start"

# Remove a workspace
[group('workbench')]
workspace-remove name:
    #!/usr/bin/env bash
    set -eo pipefail
    wb_root="{{ justfile_directory() }}"
    ws="$wb_root/workspaces/{{ name }}"
    if [[ ! -d "$ws" ]]; then
        echo "Error: workspace '{{ name }}' not found" >&2
        exit 1
    fi
    # Stop server if running
    pgid=$(jq -r '.server.pgid // empty' "$ws/.workspace_info.json" 2>/dev/null)
    if [[ -n "$pgid" ]]; then
        echo "Stopping server..."
        kill -TERM -- -"$pgid" 2>/dev/null || true
        sleep 1
    fi
    rm -rf "$ws"
    echo "✓ Removed workspace '{{ name }}'"

# Remove all workspaces and start fresh
[group('workbench')]
workspace-remove-all:
    #!/usr/bin/env bash
    set -eo pipefail
    wb_root="{{ justfile_directory() }}"
    for ws in "$wb_root"/workspaces/*/; do
        [[ -d "$ws" ]] || continue
        name=$(basename "$ws")
        # Stop server if running
        pgid=$(jq -r '.server.pgid // empty' "$ws/.workspace_info.json" 2>/dev/null)
        if [[ -n "$pgid" ]]; then
            kill -TERM -- -"$pgid" 2>/dev/null || true
        fi
        echo "Removing $name..."
    done
    rm -rf "$wb_root/workspaces"
    echo "✓ All workspaces removed"


