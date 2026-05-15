set dotenv-load

root := justfile_directory()

################################################################################
# Workbench recipes (can be run anywhere within the workbench)
################################################################################

# Create a new worktree: just worktree-add <name> [--dev] <repos...> [--with <packages...>]
[group('workbench')]
worktree-add *args:
    #!/usr/bin/env bash
    set -eo pipefail
    wb_root=$(just _get_workbench_root)
    cd "$wb_root"

    # Parse arguments
    name=""
    dev_repos=()
    with_pkgs=()
    mode="dev"

    for arg in {{args}}; do
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
        url=$(jq -r --arg r "$repo" '.[$r] // empty' "$wb_root/repos.json")
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

    # Copy latest justfile into worktree
    cp "$wb_root/justfile" "$wt/justfile"
    [[ -f "$wb_root/.env" ]] && cp "$wb_root/.env" "$wt/.env"

    # Write marker
    touch "$wt/.is_worktree"

    cd "$wt"

    # Clone and dev-install repos
    for repo in "${dev_repos[@]}"; do
        url=$(jq -r --arg r "$repo" '.[$r]' "$wb_root/repos.json")
        echo "Cloning $repo..."
        git clone "$url" "$repo"

        if [[ "$repo" == "jupyter-chat" ]]; then
            pkg_path="./jupyter-chat/python/jupyterlab-chat"
        else
            pkg_path="./$repo"
        fi

        uv add --editable --workspace "$pkg_path"
    done

    # Install --with packages from PyPI
    if [[ ${#with_pkgs[@]} -gt 0 ]]; then
        echo "Adding PyPI packages: ${with_pkgs[*]}"
        uv add "${with_pkgs[@]}"
    fi

    # Build and enable extensions for dev repos
    for repo in "${dev_repos[@]}"; do
        if [[ "$repo" == "jupyter-chat" ]]; then
            pkg_dir="jupyter-chat/python/jupyterlab-chat"
        else
            pkg_dir="$repo"
        fi
        pkg_toml="$pkg_dir/pyproject.toml"
        pkg_name=$(grep -m1 '^name' "$pkg_toml" | sed 's/name = "//;s/"//')

        if [[ -f "$pkg_dir/package.json" ]]; then
            echo "Building $repo frontend..."
            (cd "$pkg_dir" && uv run --project "$wt" jlpm && uv run --project "$wt" jlpm build)
        fi

        echo "Enabling server extension: $pkg_name"
        uv run jupyter server extension enable "$pkg_name" 2>/dev/null || true

        if [[ -f "$pkg_dir/package.json" ]]; then
            (cd "$pkg_dir" && uv run --project "$wt" jupyter labextension develop . --overwrite) 2>/dev/null || true
        fi
    done

    echo ""
    echo "✓ Worktree '$name' ready at: $wt"
    echo "  cd $wt && just start"

# Remove a worktree
[group('workbench')]
worktree-remove name:
    #!/usr/bin/env bash
    set -eo pipefail
    wb_root=$(just _get_workbench_root)
    wt="$wb_root/worktrees/{{name}}"
    if [[ ! -d "$wt" ]]; then
        echo "Error: worktree '{{name}}' not found" >&2
        exit 1
    fi
    cd "$wb_root"
    git worktree remove "$wt" --force
    echo "✓ Removed worktree '{{name}}'"

################################################################################
# Worktree recipes (can be run anywhere within a worktree)
################################################################################

# Add a package via uv (same as 'uv add')
[group('worktree')]
add +pkgs:
    #!/usr/bin/env bash
    set -eo pipefail
    wt_root=$(just _get_worktree_root)
    cd "$wt_root"
    uv add {{pkgs}}

# Add a package as editable (clone, build, dev-install)
[group('worktree')]
add-dev +repos:
    #!/usr/bin/env bash
    set -eo pipefail
    wt_root=$(just _get_worktree_root)
    wb_root=$(just _get_workbench_root)
    cd "$wt_root"

    # Validate repo names
    for repo in {{repos}}; do
        url=$(jq -r --arg r "$repo" '.[$r] // empty' "$wb_root/repos.json")
        if [[ -z "$url" ]]; then
            echo "Error: '$repo' not found in repos.json" >&2
            exit 1
        fi
        if [[ -d "$repo" ]]; then
            echo "Error: '$repo' already exists in this worktree" >&2
            exit 1
        fi
    done

    # Clone repos and add as editable workspace members
    for repo in {{repos}}; do
        url=$(jq -r --arg r "$repo" '.[$r]' "$wb_root/repos.json")
        echo "Cloning $repo..."
        git clone "$url" "$repo"

        if [[ "$repo" == "jupyter-chat" ]]; then
            pkg_path="./jupyter-chat/python/jupyterlab-chat"
        else
            pkg_path="./$repo"
        fi

        uv add --editable --workspace "$pkg_path"
    done

    # Build and enable extensions
    for repo in {{repos}}; do
        if [[ "$repo" == "jupyter-chat" ]]; then
            pkg_dir="jupyter-chat/python/jupyterlab-chat"
        else
            pkg_dir="$repo"
        fi
        pkg_toml="$pkg_dir/pyproject.toml"
        pkg_name=$(grep -m1 '^name' "$pkg_toml" | sed 's/name = "//;s/"//')

        if [[ -f "$pkg_dir/package.json" ]]; then
            echo "Building $repo frontend..."
            (cd "$pkg_dir" && uv run --project "$wt_root" jlpm && uv run --project "$wt_root" jlpm build)
        fi

        echo "Enabling server extension: $pkg_name"
        uv run jupyter server extension enable "$pkg_name" 2>/dev/null || true

        if [[ -f "$pkg_dir/package.json" ]]; then
            (cd "$pkg_dir" && uv run --project "$wt_root" jupyter labextension develop . --overwrite) 2>/dev/null || true
        fi
    done

    echo ""
    echo "✓ Added: {{repos}}"

# Start JupyterLab
[group('worktree')]
start *args:
    #!/usr/bin/env bash
    set -eo pipefail
    wt_root=$(just _get_worktree_root)
    wb_root=$(just _get_workbench_root)
    cd "$wt_root"
    uv run jupyter lab --config="$wb_root/jupyter_server_config.py" {{args}}

# Show which packages are dev-installed in this worktree
[group('worktree')]
worktree-status:
    #!/usr/bin/env bash
    wt_root=$(just _get_worktree_root)
    echo "Dev-installed packages:"
    grep 'editable = true' "$wt_root/pyproject.toml" | cut -d= -f1 | sed 's/^/  /'

################################################################################
# Repo recipes (can only be run from inside a repo within a worktree)
################################################################################

# Rebuild frontend for the current repo
[group('repo')]
build:
    #!/usr/bin/env bash
    set -eo pipefail
    just _require_worktree_repo
    wt_root=$(just _get_worktree_root)
    cd {{ invocation_directory() }}
    uv run --project "$wt_root" jlpm build

################################################################################
# Internal helpers
################################################################################

# Print the workbench root path (walks up from cwd)
_get_workbench_root:
    #!/usr/bin/env bash
    dir="$(pwd)"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/repos.json" && ! -f "$dir/.is_worktree" ]]; then
            echo "$dir"
            exit 0
        fi
        dir="$(dirname "$dir")"
    done
    echo "Error: not inside a jupyter-workbench" >&2
    exit 1

# Print the worktree root path (walks up from cwd looking for .is_worktree)
_get_worktree_root:
    #!/usr/bin/env bash
    dir="$(pwd)"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/.is_worktree" ]]; then
            echo "$dir"
            exit 0
        fi
        dir="$(dirname "$dir")"
    done
    echo "Error: not inside a worktree" >&2
    exit 1

# Exits non-0 if not inside a repo under a worktree
_require_worktree_repo:
    #!/usr/bin/env bash
    if [[ -f .is_worktree ]]; then
        echo "Error: run this from inside a repo, not the worktree root" >&2
        exit 1
    fi
    dir="$(pwd)"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/.is_worktree" ]]; then
            exit 0
        fi
        dir="$(dirname "$dir")"
    done
    echo "Error: not inside a worktree repo. Run this from within worktrees/<name>/<repo>/..." >&2
    exit 1
