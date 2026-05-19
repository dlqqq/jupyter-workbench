set dotenv-load := true

# Echo the workbench root directory
[group('workbench')]
get-workbench-root:
    @echo "{{ justfile_directory() }}"

# List all available recipes
[group('workbench')]
list-recipes:
    @just --list --list-heading=""

# Create a new workspace
[group('workbench')]
[arg("name", help="workspace name")]
[arg("dev", long, help="comma-separated repos to dev-install")]
[arg("with_pkgs", long="with", help="comma-separated PyPI packages to add")]
add-workspace name dev="" with_pkgs="":
    #!/usr/bin/env bash
    set -eo pipefail
    wb_root="{{ justfile_directory() }}"
    cd "$wb_root"

    name="{{ name }}"
    IFS=',' read -ra dev_repos <<< "{{ dev }}"
    IFS=',' read -ra with_pkgs <<< "{{ with_pkgs }}"

    # Remove empty elements from empty defaults
    [[ -z "${dev_repos[0]}" ]] && dev_repos=()
    [[ -z "${with_pkgs[0]}" ]] && with_pkgs=()

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
    cp "$wb_root/workspaces/templates/"* "$ws/"

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

    cmux_ws=$(cmux new-workspace --name "[ws] $name" --cwd "$ws")
    echo ""
    echo "✓ Workspace '$name' ready at: $ws"
    echo "✓ cmux workspace ready: $cmux_ws"
    echo "  cd $ws && just start-server"

# Remove workspaces (comma-separated, or --all)
[group('workbench')]
[arg("names", help="comma-separated workspace names (ignored with --all)")]
[arg("all", long, value="true")]
remove-workspaces names="" all="false":
    #!/usr/bin/env bash
    set -eo pipefail
    wb_root="{{ justfile_directory() }}"

    if [[ "{{ all }}" == "true" ]]; then
        for ws in "$wb_root"/workspaces/*/; do
            [[ -d "$ws" ]] || continue
            name=$(basename "$ws")
            pgid=$(jq -r '.server.pgid // empty' "$ws/.workspace_info.json" 2>/dev/null)
            if [[ -n "$pgid" ]]; then
                kill -TERM -- -"$pgid" 2>/dev/null || true
            fi
            echo "Removing $name..."
        done
        rm -rf "$wb_root/workspaces"
        echo "✓ All workspaces removed"
    else
        if [[ -z "{{ names }}" ]]; then
            echo "Usage: just remove-workspaces <names> or just remove-workspaces --all" >&2
            exit 1
        fi
        IFS=',' read -ra name_list <<< "{{ names }}"
        for name in "${name_list[@]}"; do
            ws="$wb_root/workspaces/$name"
            if [[ ! -d "$ws" ]]; then
                echo "Error: workspace '$name' not found" >&2
                exit 1
            fi
            pgid=$(jq -r '.server.pgid // empty' "$ws/.workspace_info.json" 2>/dev/null)
            if [[ -n "$pgid" ]]; then
                echo "Stopping server..."
                kill -TERM -- -"$pgid" 2>/dev/null || true
                sleep 1
            fi
            rm -rf "$ws"
            echo "✓ Removed workspace '$name'"
        done
    fi



# Create a workbench worktree (for modifying workbench infrastructure)
[group('workbench')]
[arg("name", help="worktree/branch name")]
add-worktree name:
    #!/usr/bin/env bash
    set -eo pipefail
    wb_root="{{ justfile_directory() }}"
    wt="$wb_root/worktrees/{{ name }}"
    if [[ -d "$wt" ]]; then
        echo "Error: worktree '{{ name }}' already exists" >&2
        exit 1
    fi
    mkdir -p "$wb_root/worktrees"
    git worktree add -b "{{ name }}" "$wt"
    cmux_ws=$(cmux new-workspace --name "[wb-wt] {{ name }}" --cwd "$wt")
    echo "✓ Worktree '{{ name }}' ready at: $wt"
    echo "✓ cmux workspace ready: $cmux_ws"
    echo "  cd $wt"

# Remove a workbench worktree
[group('workbench')]
[arg("name", help="worktree name")]
[arg("force", long, value="true")]
remove-worktree name force="false":
    #!/usr/bin/env bash
    set -eo pipefail
    wb_root="{{ justfile_directory() }}"
    wt="$wb_root/worktrees/{{ name }}"
    if [[ ! -d "$wt" ]]; then
        echo "Error: worktree '{{ name }}' not found" >&2
        exit 1
    fi

    if [[ "{{ force }}" != "true" ]]; then
        # Check for uncommitted changes
        if [[ -n "$(git -C "$wt" status --porcelain)" ]]; then
            echo "Error: worktree '{{ name }}' has uncommitted changes. Use --force to override." >&2
            exit 1
        fi
        # Check if branch is merged
        if ! git merge-base --is-ancestor "{{ name }}" main; then
            echo "Error: branch '{{ name }}' has unmerged commits. Push and merge first, or use --force." >&2
            exit 1
        fi
    fi

    git worktree remove "$wt" --force
    git branch -D "{{ name }}" 2>/dev/null || true
    echo "✓ Removed worktree '{{ name }}'"
