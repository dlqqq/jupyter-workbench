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
    get_workbench_root "{{ invocation }}" || exit 1
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
    cp -r "$WB_ROOT/scripts" "$wt/scripts"
    [[ -f "$WB_ROOT/.env" ]] && cp "$WB_ROOT/.env" "$wt/.env"

    # Write worktree info with repo list
    touch "$wt/.worktree_info"
    for repo in "${dev_repos[@]}"; do
        echo "$repo" >> "$wt/.worktree_info"
    done

    cd "$wt"

    # Clone and dev-install repos
    for repo in "${dev_repos[@]}"; do
        url=$(jq -r --arg r "$repo" '.[$r].url' "$WB_ROOT/repos.json")
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
    # for repo in "${dev_repos[@]}"; do
    #     if [[ "$repo" == "jupyter-chat" ]]; then
    #         pkg_dir="jupyter-chat/python/jupyterlab-chat"
    #     else
    #         pkg_dir="$repo"
    #     fi
    #     pkg_toml="$pkg_dir/pyproject.toml"
    #     pkg_name=$(grep -m1 '^name' "$pkg_toml" | sed 's/name = "//;s/"//')

    #     if [[ -f "$pkg_dir/package.json" ]]; then
    #         echo "Building $repo frontend..."
    #         (cd "$pkg_dir" && uv run --project "$wt" jlpm && uv run --project "$wt" jlpm build)
    #     fi

    #     echo "Enabling server extension: $pkg_name"
    #     uv run jupyter server extension enable "$pkg_name" 2>/dev/null || true

    #     if [[ -f "$pkg_dir/package.json" ]]; then
    #         (cd "$pkg_dir" && uv run --project "$wt" jupyter labextension develop . --overwrite) 2>/dev/null || true
    #     fi
    # done

    echo ""
    echo "✓ Worktree '$name' ready at: $wt"
    echo "  cd $wt && just start"

# Remove a worktree
[group('workbench')]
worktree-remove name:
    #!/usr/bin/env bash
    set -eo pipefail
    source "{{ helpers }}"
    get_workbench_root "{{ invocation }}" || exit 1
    wt="$WB_ROOT/worktrees/{{ name }}"
    if [[ ! -d "$wt" ]]; then
        echo "Error: worktree '{{ name }}' not found" >&2
        exit 1
    fi
    cd "$WB_ROOT"
    git worktree remove "$wt" --force
    echo "✓ Removed worktree '{{ name }}'"

################################################################################
# Worktree recipes (can be run anywhere within a worktree)
################################################################################

# Add a package via uv (same as 'uv add')
[group('worktree')]
add +pkgs:
    #!/usr/bin/env bash
    set -eo pipefail
    source "{{ helpers }}"
    get_worktree_root "{{ invocation }}" || exit 1
    cd "$WT_ROOT"
    uv add {{ pkgs }}

# Add a package as editable (clone, build, dev-install)
[group('worktree')]
add-dev +repos:
    #!/usr/bin/env bash
    set -eo pipefail
    source "{{ helpers }}"
    get_worktree_root "{{ invocation }}" || exit 1
    get_workbench_root "{{ invocation }}" || exit 1
    cd "$WT_ROOT"

    # Validate repo names
    for repo in {{ repos }}; do
        url=$(jq -r --arg r "$repo" '.[$r].url // empty' "$WB_ROOT/repos.json")
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
    for repo in {{ repos }}; do
        url=$(jq -r --arg r "$repo" '.[$r].url' "$WB_ROOT/repos.json")
        echo "Cloning $repo..."
        git clone "$url" "$repo"

        if [[ "$repo" == "jupyter-chat" ]]; then
            pkg_path="./jupyter-chat/python/jupyterlab-chat"
        else
            pkg_path="./$repo"
        fi

        uv add --editable --workspace "$pkg_path"
    done

    # Update .worktree_info
    for repo in {{ repos }}; do
        echo "$repo" >> "$WT_ROOT/.worktree_info"
    done

    echo ""
    echo "✓ Added: {{ repos }}"

# Start JupyterLab
[group('worktree')]
start *args:
    #!/usr/bin/env bash
    set -eo pipefail
    source "{{ helpers }}"
    get_worktree_root "{{ invocation }}" || exit 1
    get_workbench_root "{{ invocation }}" || exit 1
    cd "$WT_ROOT"
    uv run jupyter lab --config="$WB_ROOT/jupyter_server_config.py" {{ args }}

# Show which packages are dev-installed in this worktree
[group('worktree')]
worktree-status:
    #!/usr/bin/env bash
    source "{{ helpers }}"
    get_worktree_root "{{ invocation }}" || exit 1
    echo "Dev-installed packages:"
    grep 'editable = true' "$WT_ROOT/pyproject.toml" | cut -d= -f1 | sed 's/^/  /'

# Enable extensions for all dev-installed repos in this worktree
[group('worktree')]
enable-all-extensions:
    #!/usr/bin/env bash
    set -eo pipefail
    source "{{ helpers }}"
    get_worktree_root "{{ invocation }}" || exit 1
    get_worktree_repos
    for repo in "${WT_REPOS[@]}"; do
        echo "=== $repo ==="
        cd $repo
        just enable-repo-extensions
    done

################################################################################
# Repo recipes (can only be run from inside a repo within a worktree)
#
# These use [no-cd] so they run from the directory where `just` was invoked,
# rather than justfile_directory(). This allows worktree recipes to
# `cd $repo && just <repo-recipe>` and have it work correctly.
################################################################################

# Rebuild frontend for the current repo
[group('repo')]
[no-cd]
build:
    #!/usr/bin/env bash
    set -eo pipefail
    source "{{ helpers }}"
    get_worktree_repo "{{ invocation }}" || exit 1
    cd "$REPO_ROOT"
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
