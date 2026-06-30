#!/usr/bin/env bash

load helpers

setup() { wb_setup; }
teardown() { wb_teardown; }

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

@test "ws create writes runtime-only .workspace_info.json (no dev-repos/prompt)" {
    just ws create "$TEST_WS_NAME"
    [ -f "$TEST_WS/.workspace_info.json" ]
    # Has runtime keys
    run jq -e 'has("server") and has("browser") and has("agent")' "$TEST_WS/.workspace_info.json"
    [ "$status" -eq 0 ]
    # Does NOT have dev-repos or prompt
    run jq -e 'has("dev-repos") or has("prompt")' "$TEST_WS/.workspace_info.json"
    [ "$status" -ne 0 ]
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

@test "ws create initializes an empty (activatable) venv" {
    just ws create "$TEST_WS_NAME"
    [ -f "$TEST_WS/.venv/bin/activate" ]
}

@test "ws create leaves no uncommitted/dirty git changes in the workspace" {
    just ws create "$TEST_WS_NAME"
    dirty=$(git -C "$TEST_WS" status --porcelain)
    [ -z "$dirty" ]
}

@test "ws create without cmux prints setup instructions" {
    # helpers unsets CMUX_WORKSPACE_ID
    run just ws create "$TEST_WS_NAME"
    [ "$status" -eq 0 ]
    [[ "$output" == *"cd workspaces/$TEST_WS_NAME"* ]]
    [[ "$output" == *"source .venv/bin/activate"* ]]
    [[ "$output" == *"just dev setup"* ]]
}

@test "ws create points at the setup.sh + ws setup flow" {
    run just ws create "$TEST_WS_NAME"
    [ "$status" -eq 0 ]
    [[ "$output" == *"setup.sh"* ]]
    [[ "$output" == *"just ws setup $TEST_WS_NAME"* ]]
}

@test "ws setup errors when the workspace is missing" {
    run just ws setup "no-such-ws-xyz"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}

@test "ws setup errors when setup.sh is missing" {
    just ws create "$TEST_WS_NAME" >/dev/null
    run just ws setup "$TEST_WS_NAME"
    [ "$status" -ne 0 ]
    [[ "$output" == *"setup.sh"* ]]
}

@test "ws setup runs the workspace's setup.sh (no-cmux path)" {
    just ws create "$TEST_WS_NAME" >/dev/null
    printf '#!/usr/bin/env bash\necho ran-setup-marker\n' > "$TEST_WS/setup.sh"
    run just ws setup "$TEST_WS_NAME"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ran-setup-marker"* ]]
}

@test "ws rm removes the workspace directory immediately" {
    just ws create "$TEST_WS_NAME" >/dev/null
    run just ws rm "$TEST_WS_NAME"
    [ "$status" -eq 0 ]
    [ ! -d "$TEST_WS" ]
}

@test "ws rm deletes the workspace branch" {
    just ws create "$TEST_WS_NAME" >/dev/null
    just ws rm "$TEST_WS_NAME"
    run git -C "$WB_ROOT" show-ref --verify --quiet "refs/heads/$(date +%Y%m%d)-$TEST_WS_NAME"
    [ "$status" -ne 0 ]
}

@test "ws rm errors on unknown workspace" {
    run just ws rm "no-such-ws-xyz"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found"* ]]
}
