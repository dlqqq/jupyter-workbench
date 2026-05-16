#!/usr/bin/env bash
# Shared helper functions for jupyter-workbench recipes.
# Source this, then call functions. They set global variables directly.
# All functions accept a starting directory as $1 (required).

# Sets: WB_ROOT
get_workbench_root() {
    local dir="$1"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/repos.json" && ! -f "$dir/.is_worktree" ]]; then
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
        if [[ -f "$dir/.is_worktree" ]]; then
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
