#!/usr/bin/env bash
# Shared setup/teardown helpers for workbench tests.
# Named distinctly (wb_*) so test-file setup()/teardown() can call them
# without shadowing the bats-reserved function names.

WB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

wb_setup() {
    TEST_ID="test-$$-$RANDOM"
    TEST_WS_NAME="$TEST_ID"
    TEST_WS="$WB_ROOT/workspaces/$TEST_WS_NAME"
    # Ensure recipes take the no-cmux path
    unset CMUX_WORKSPACE_ID
}

wb_teardown() {
    if [[ -d "$TEST_WS" ]]; then
        git worktree remove "$TEST_WS" --force 2>/dev/null || rm -rf "$TEST_WS"
    fi
    git branch -D "$(date +%Y%m%d)-$TEST_WS_NAME" 2>/dev/null || true
    # Sweep any trash left by `ws rm`/`cleanup` background jobs
    rm -rf "$WB_ROOT/workspaces/.trash" 2>/dev/null || true
    git -C "$WB_ROOT" worktree prune 2>/dev/null || true
}
