set dotenv-load

root := justfile_directory()

# Create a new worktree with specified repos for development
worktree-create name +repos:
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

    # Write marker
    touch "$wt/.is_worktree"

    # Clone repos
    for repo in {{repos}}; do
        url=$(jq -r --arg r "$repo" '.[$r]' "{{root}}/repos.json")
        echo "Cloning $repo..."
        git clone "$url" "$wt/$repo"
    done

    # Patch pyproject.toml
    cd "$wt"
    python3 "{{root}}/scripts/patch_pyproject.py" {{repos}}

    # uv sync
    echo "Running uv sync..."
    uv sync

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

# Add repos to an existing worktree
worktree-add +repos:
    #!/usr/bin/env bash
    set -euo pipefail

    if [[ ! -f .is_worktree ]]; then
        echo "Error: not in a worktree. Run this from inside worktrees/<name>/" >&2
        exit 1
    fi

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

    # Clone repos
    for repo in {{repos}}; do
        url=$(jq -r --arg r "$repo" '.[$r]' "{{root}}/repos.json")
        echo "Cloning $repo..."
        git clone "$url" "$repo"
    done

    # Patch pyproject.toml
    python3 "{{root}}/scripts/patch_pyproject.py" {{repos}}

    # uv sync
    echo "Running uv sync..."
    uv sync

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
            (cd "$pkg_dir" && uv run --project "$(pwd)" jlpm && uv run --project "$(pwd)" jlpm build)
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
start *args:
    uv run jupyter lab --config={{root}}/jupyter_server_config.py {{args}}

# Rebuild frontend for all dev packages in this worktree
build:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ ! -f .is_worktree ]]; then
        echo "Error: not in a worktree" >&2
        exit 1
    fi
    for repo in $(jq -r 'keys[]' "{{root}}/repos.json"); do
        if [[ "$repo" == "jupyter-chat" ]]; then
            pkg_dir="jupyter-chat/python/jupyterlab-chat"
        else
            pkg_dir="$repo"
        fi
        if [[ -d "$pkg_dir" && -f "$pkg_dir/package.json" ]]; then
            echo "Building $repo..."
            (cd "$pkg_dir" && uv run --project "$(pwd)/.." jlpm build)
        fi
    done

# Show which packages are dev-installed in this worktree
worktree-status:
    #!/usr/bin/env bash
    if [[ ! -f .is_worktree ]]; then
        echo "Error: not in a worktree" >&2
        exit 1
    fi
    echo "Dev-installed packages:"
    sed -n '/# --- workspace packages (editable) ---/,/^\]/p' pyproject.toml \
        | grep -v '^\]' | grep -v '# ---' | sed 's/[", ]//g' | grep -v '^$' | sed 's/^/  /'
