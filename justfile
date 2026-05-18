set dotenv-load := true

# Echo the workbench root directory
[group('workbench')]
get-workbench-root:
    @echo "{{ justfile_directory() }}"

# List all available recipes
[group('workbench')]
list-recipes:
    @just --list --list-heading=""

# Create a new worktree: just worktree-add <name> [--dev] <repos...> [--with <packages...>]
[group('workbench')]
worktree-add *args:
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
        echo "Usage: just worktree-add <name> [--dev <repos...>] [--with <packages...>]" >&2
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

    wt="$wb_root/worktrees/$name"
    if [[ -d "$wt" ]]; then
        echo "Error: worktree '$name' already exists at $wt" >&2
        exit 1
    fi

    # Create worktree (detached)
    mkdir -p "$wb_root/worktrees"
    git worktree add --detach "$wt"

    # Symlink worktree justfile and skills to workbench root
    ln -sf "$wb_root/worktree.just" "$wt/justfile"
    rm -rf "$wt/.kiro/skills"
    mkdir -p "$wt/.kiro"
    ln -sf "$wb_root/.kiro/skills" "$wt/.kiro/skills"
    [[ -f "$wb_root/.env" ]] && cp "$wb_root/.env" "$wt/.env"

    cd "$wt"

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
    echo "✓ Worktree '$name' ready at: $wt"
    echo "  cd $wt && just server-start"

# Remove a worktree
[group('workbench')]
worktree-remove name:
    #!/usr/bin/env bash
    set -eo pipefail
    wb_root="{{ justfile_directory() }}"
    wt="$wb_root/worktrees/{{ name }}"
    if [[ ! -d "$wt" ]]; then
        echo "Error: worktree '{{ name }}' not found" >&2
        exit 1
    fi
    cd "$wb_root"
    git worktree remove "$wt" --force
    echo "✓ Removed worktree '{{ name }}'"

# Remove all worktrees and start fresh
[group('workbench')]
worktree-remove-all:
    #!/usr/bin/env bash
    set -eo pipefail
    wb_root="{{ justfile_directory() }}"
    cd "$wb_root"
    for wt in worktrees/*/; do
        [[ -d "$wt" ]] || continue
        name=$(basename "$wt")
        echo "Removing $name..."
        git worktree remove "$wt" --force
    done
    rm -rf worktrees
    echo "✓ All worktrees removed"


