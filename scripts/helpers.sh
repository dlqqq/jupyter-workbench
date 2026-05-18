#!/usr/bin/env bash
# Shared helper functions for jupyter-workbench recipes.
# Source this, then call functions. They set global variables directly.
# All functions accept a starting directory as $1 (required).

# Sets: WB_ROOT
get_workbench_root() {
    local dir="$1"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/repos.json" && ! -f "$dir/.worktree_info" ]]; then
            WB_ROOT="$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    echo "Error: not inside a jupyter-workbench" >&2
    return 1
}

# Sets: WT_ROOT
get_worktree_root() {
    local dir="$1"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/.worktree_info" ]]; then
            WT_ROOT="$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    echo "Error: not inside a worktree" >&2
    return 1
}

# Sets: REPO_ROOT, REPO_NAME
get_worktree_repo() {
    local dir="$1"
    get_worktree_root "$dir" || return 1
    if [[ "$dir" == "$WT_ROOT" ]]; then
        echo "Error: run this from inside a repo, not the worktree root" >&2
        return 1
    fi
    while [[ "$dir" != "$WT_ROOT" && "$dir" != "/" ]]; do
        if [[ -d "$dir/.git" || -f "$dir/.git" ]]; then
            REPO_ROOT="$dir"
            REPO_NAME="$(basename "$dir")"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    echo "Error: not inside a repo within this worktree" >&2
    return 1
}

# Sets: WT_REPOS (array of repo names in this worktree)
# Requires: WT_ROOT to be set
get_worktree_repos() {
    WT_REPOS=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && WT_REPOS+=("$line")
    done < "$WT_ROOT/.worktree_info"
}

# Sets: PKG_NAMES (array of Python package names for this repo)
# Requires: WB_ROOT, REPO_NAME to be set
get_repo_pkg_names() {
    local json="$WB_ROOT/repos.json"
    local raw
    raw=$(jq -r --arg r "$REPO_NAME" '
        .[$r].packages // [{"name": ($r | gsub("-";"_"))}]
        | .[].name
    ' "$json")
    PKG_NAMES=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && PKG_NAMES+=("$line")
    done <<< "$raw"
}

# Sets: PKG_PARENT_DIRS (array of paths from repo root to pyproject.toml dirs)
# Requires: WB_ROOT, REPO_NAME to be set
get_repo_pkg_parents() {
    local json="$WB_ROOT/repos.json"
    local raw
    raw=$(jq -r --arg r "$REPO_NAME" '
        .[$r].packages // [{"parentDir": "."}]
        | .[].parentDir
    ' "$json")
    PKG_PARENT_DIRS=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && PKG_PARENT_DIRS+=("$line")
    done <<< "$raw"
}

# Errors if a Jupyter server is already running in this worktree
# Requires: WT_ROOT to be set
check_no_server_running() {
    local running
    running=$(uv run jupyter server list --jsonlist 2>/dev/null | jq -r --arg root "$WT_ROOT" '.[] | select(.root_dir == $root) | .url' | head -1)
    if [[ -n "$running" ]]; then
        echo "Error: a Jupyter server is already running at $running" >&2
        echo "Stop it before starting a new one." >&2
        return 1
    fi
}
