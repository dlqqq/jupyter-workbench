#!/usr/bin/env bash
# Shared setup/teardown for workbench tests

WB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

setup() {
    TEST_ID="test-$$-$RANDOM"
    TEST_WS_NAME="$TEST_ID"
    TEST_WS="$WB_ROOT/workspaces/$TEST_WS_NAME"
    # Unset CMUX to ensure recipes skip cmux logic
    unset CMUX_WORKSPACE_ID
}

teardown() {
    if [[ -d "$TEST_WS" ]]; then
        git worktree remove "$TEST_WS" --force 2>/dev/null || rm -rf "$TEST_WS"
    fi
    git branch -D "$(date +%Y%m%d)-$TEST_WS_NAME" 2>/dev/null || true
}
