set dotenv-load

root := justfile_directory()

################################################################################
# Workbench recipes
################################################################################

# Create a new worktree with specified repos for development
worktree-add name +repos: _require_workbench_root
    #!/usr/bin/env bash
    set -euo pipefail

    # Validate repo names
    for repo in {{repos}}; do
        url=$(jq -r --arg r "$repo" '.[$r] // empty' "{{root}}/repos.json")
        if [[ -z "$url" ]]; then
            echo "Error: '$repo' not found in repos.json" >&2
            echo "Available repos: $(jq -r 'keys[]' "{{root}}/repos.json" | tr '\n' ' ')" >&2
            exit 1
        fi
    done

    wt="{{root}}/worktrees/{{name}}"
    if [[ -d "$wt" ]]; then
        echo "Error: worktree '{{name}}' already exists at $wt" >&2
        exit 1
    fi

    # Create worktree (detached)
    mkdir -p "{{root}}/worktrees"
    git worktree add --detach "$wt"

    # Copy latest justfile into worktree
    cp "{{root}}/justfile" "$wt/justfile"

    # Write marker
    touch "$wt/.is_worktree"

    # Clone repos and add as editable workspace members
    cd "$wt"
    for repo in {{repos}}; do
        url=$(jq -r --arg r "$repo" '.[$r]' "{{root}}/repos.json")
        echo "Cloning $repo..."
        git clone "$url" "$repo"

        # Determine the package path within the repo
        if [[ "$repo" == "jupyter-chat" ]]; then
            pkg_path="./jupyter-chat/python/jupyterlab-chat"
        else
            pkg_path="./$repo"
        fi

        # Add to workspace members, then let uv handle the rest
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
            (cd "$pkg_dir" && uv run --project "$wt" jlpm && uv run --project "$wt" jlpm build)
        fi

        echo "Enabling server extension: $pkg_name"
        uv run jupyter server extension enable "$pkg_name" 2>/dev/null || true

        if [[ -f "$pkg_dir/package.json" ]]; then
            (cd "$pkg_dir" && uv run --project "$wt" jupyter labextension develop . --overwrite) 2>/dev/null || true
        fi
    done

    echo ""
    echo "✓ Worktree '{{name}}' ready at: $wt"
    echo "  cd $wt && just start"

# Remove a worktree
worktree-remove name: _require_workbench_root
    #!/usr/bin/env bash
    set -euo pipefail
    wt="{{root}}/worktrees/{{name}}"
    if [[ ! -d "$wt" ]]; then
        echo "Error: worktree '{{name}}' not found" >&2
        exit 1
    fi
    git worktree remove "$wt" --force
    echo "✓ Removed worktree '{{name}}'"

################################################################################
# Worktree recipes
################################################################################

# Add a package via uv (same as 'uv add')
add +pkgs: _require_worktree
    uv add {{pkgs}}

# Add a package as editable (clone, build, dev-install)
add-dev +repos: _require_worktree
    #!/usr/bin/env bash
    set -euo pipefail

    # Validate repo names
    for repo in {{repos}}; do
        url=$(jq -r --arg r "$repo" '.[$r] // empty' "{{root}}/repos.json")
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
        url=$(jq -r --arg r "$repo" '.[$r]' "{{root}}/repos.json")
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
            (cd "$pkg_dir" && uv run --project "$(pwd)/.." jlpm && uv run --project "$(pwd)/.." jlpm build)
        fi

        echo "Enabling server extension: $pkg_name"
        uv run jupyter server extension enable "$pkg_name" 2>/dev/null || true

        if [[ -f "$pkg_dir/package.json" ]]; then
            (cd "$pkg_dir" && uv run --project "$(pwd)/.." jupyter labextension develop . --overwrite) 2>/dev/null || true
        fi
    done

    echo ""
    echo "✓ Added: {{repos}}"

# Start JupyterLab
start *args: _require_worktree
    uv run jupyter lab --config={{root}}/jupyter_server_config.py {{args}}

# Show which packages are dev-installed in this worktree
worktree-status: _require_worktree
    #!/usr/bin/env bash
    echo "Dev-installed packages:"
    grep 'editable = true' pyproject.toml | cut -d= -f1 | sed 's/^/  /'

################################################################################
# Repo recipes
################################################################################

# Rebuild frontend for the current repo
build: _require_worktree_repo
    #!/usr/bin/env bash
    set -euo pipefail
    cd {{ invocation_directory() }}
    # Walk up to find worktree root
    wt_root="$(pwd)"
    while [[ ! -f "$wt_root/.is_worktree" ]]; do
        wt_root="$(dirname "$wt_root")"
    done
    uv run --project "$wt_root" jlpm build

################################################################################
# Internal helpers
################################################################################

# Exits 0 if at the workbench root
_require_workbench_root:
    #!/usr/bin/env bash
    if [[ -f .is_worktree ]]; then
        echo "Error: this command must be run from the workbench root, not a worktree" >&2
        exit 1
    fi
    toplevel="$(git rev-parse --show-toplevel 2>/dev/null)"
    if [[ -z "$toplevel" ]] || ! grep -q 'name = "jupyter-workbench"' "$toplevel/pyproject.toml" 2>/dev/null; then
        echo "Error: this command must be run from the workbench root" >&2
        exit 1
    fi

# Exits 0 if at a worktree root (has .is_worktree in cwd)
_require_worktree:
    #!/usr/bin/env bash
    if [[ ! -f .is_worktree ]]; then
        echo "Error: not in a worktree root. Run this from worktrees/<name>/" >&2
        exit 1
    fi

# Exits 0 if inside a repo under a worktree (not at the worktree root itself)
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
