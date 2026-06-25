#!/usr/bin/env bash

setup() {
    load helpers
    setup
}

teardown() {
    load helpers
    teardown
}

@test "ws create creates a worktree at workspaces/<name>" {
    run just ws create "$TEST_WS_NAME"
    [ "$status" -eq 0 ]
    [ -d "$TEST_WS" ]
}

@test "ws create puts worktree on YYYYMMDD-<name> branch" {
    just ws create "$TEST_WS_NAME"
    branch=$(git -C "$TEST_WS" branch --show-current)
    [[ "$branch" == "$(date +%Y%m%d)-$TEST_WS_NAME" ]]
}

@test "ws create writes .workspace_info.json" {
    just ws create "$TEST_WS_NAME"
    [ -f "$TEST_WS/.workspace_info.json" ]
    # Verify structure
    run jq -e '.["dev-repos"]' "$TEST_WS/.workspace_info.json"
    [ "$status" -eq 0 ]
}

@test "ws create symlinks pre-cloned repos into workspace repos/" {
    # Only test if any repos are pre-cloned (directories, not just justfile)
    local repo_count
    repo_count=$(find "$WB_ROOT/repos" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
    if [ "$repo_count" -eq 0 ]; then
        skip "no pre-cloned repos available"
    fi
    just ws create "$TEST_WS_NAME"
    [ -d "$TEST_WS/repos" ]
    # At least one symlink exists
    found=false
    for link in "$TEST_WS/repos/"*; do
        [ -L "$link" ] && found=true && break
    done
    [ "$found" = "true" ]
}

@test "ws create fails if workspace already exists" {
    just ws create "$TEST_WS_NAME"
    run just ws create "$TEST_WS_NAME"
    [ "$status" -ne 0 ]
    [[ "$output" == *"already exists"* ]]
}

@test "ws create sets the venv/project name to the workspace name" {
    just ws create "$TEST_WS_NAME"
    name=$(grep '^name = ' "$TEST_WS/pyproject.toml" | head -1 | sed 's/^name = "\(.*\)"/\1/')
    [ "$name" = "$TEST_WS_NAME" ]
}

@test "ws create leaves no uncommitted/dirty git changes in the workspace" {
    just ws create "$TEST_WS_NAME"
    dirty=$(git -C "$TEST_WS" status --porcelain)
    [ -z "$dirty" ]
}
