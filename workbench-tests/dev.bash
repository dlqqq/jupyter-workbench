#!/usr/bin/env bash
# Hermetic tests for `just dev add` / `just dev remove`.
# Uses a local fake source repo so no network/clone is needed.

load helpers

FAKE=fakedevpkg

setup() {
    wb_setup   # sets TEST_ID / TEST_WS_NAME / TEST_WS, unsets CMUX_WORKSPACE_ID

    # Create the workspace (runs from the main checkout's recipe)
    just ws create "$TEST_WS_NAME" >/dev/null

    # Replace pyproject with a minimal, dependency-free one so uv stays offline
    cat > "$TEST_WS/pyproject.toml" <<EOF
[project]
name = "$TEST_WS_NAME"
version = "0.0.0"
requires-python = ">=3.10"

[tool.uv.workspace]
members = []
EOF

    # Build a fake source repo under the workbench repos/ (gitignored)
    FAKE_SRC="$WB_ROOT/repos/$FAKE"
    rm -rf "$FAKE_SRC"
    mkdir -p "$FAKE_SRC/$FAKE"
    cat > "$FAKE_SRC/pyproject.toml" <<EOF
[project]
name = "$FAKE"
version = "0.0.1"
requires-python = ">=3.10"

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"
EOF
    echo "" > "$FAKE_SRC/$FAKE/__init__.py"
    git -C "$FAKE_SRC" init -q
    git -C "$FAKE_SRC" add -A
    git -C "$FAKE_SRC" -c user.email=t@t.dev -c user.name=test commit -qm init

    # Register the fake repo in the workspace's repos.json
    jq --arg r "$FAKE" --arg u "$FAKE_SRC" \
        '.[$r] = {"url": $u, "packages": [{"name": $r, "parentDir": "."}]}' \
        "$TEST_WS/repos.json" > "$TEST_WS/repos.json.tmp" \
        && mv "$TEST_WS/repos.json.tmp" "$TEST_WS/repos.json"
}

teardown() {
    # Remove any dev worktree created off the fake source
    if [ -d "$TEST_WS/dev/$FAKE" ]; then
        git -C "$WB_ROOT/repos/$FAKE" worktree remove "$TEST_WS/dev/$FAKE" --force 2>/dev/null || true
    fi
    wb_teardown   # removes the workspace worktree + branch
    rm -rf "$WB_ROOT/repos/$FAKE"
}

@test "dev add creates a worktree under dev/" {
    cd "$TEST_WS"
    run just dev add "$FAKE"
    [ "$status" -eq 0 ]
    [ -d "$TEST_WS/dev/$FAKE" ]
    [ -e "$TEST_WS/dev/$FAKE/.git" ]
}

@test "dev add puts the dev worktree on a YYYYMMDD-<ws>/<repo> branch" {
    cd "$TEST_WS"
    just dev add "$FAKE"
    branch=$(git -C "$TEST_WS/dev/$FAKE" branch --show-current)
    [[ "$branch" == "$(date +%Y%m%d)-$TEST_WS_NAME/$FAKE" ]]
}

@test "dev add adds the workspace member to pyproject.toml" {
    cd "$TEST_WS"
    just dev add "$FAKE"
    grep -q "dev/$FAKE" "$TEST_WS/pyproject.toml"
}

@test "dev add does NOT write dev-repos to .workspace_info.json" {
    cd "$TEST_WS"
    just dev add "$FAKE"
    run jq -e 'has("dev-repos")' "$TEST_WS/.workspace_info.json"
    [ "$status" -ne 0 ]
}

@test "dev add errors on unknown repo" {
    cd "$TEST_WS"
    run just dev add "no-such-repo-xyz"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found in repos.json"* ]]
}

@test "dev add errors if repo already dev-installed" {
    cd "$TEST_WS"
    just dev add "$FAKE"
    run just dev add "$FAKE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"already dev-installed"* ]]
}

@test "dev remove removes the worktree and the pyproject member" {
    cd "$TEST_WS"
    just dev add "$FAKE"
    run just dev remove "$FAKE"
    [ "$status" -eq 0 ]
    [ ! -d "$TEST_WS/dev/$FAKE" ]
    run grep -q "dev/$FAKE" "$TEST_WS/pyproject.toml"
    [ "$status" -ne 0 ]
}
