#!/usr/bin/env bash
# Tests for `just repos` recipes.

load helpers

FAKE=__test_fakerepo__

setup() {
    wb_setup
    rm -rf "$WB_ROOT/repos/$FAKE"
    git init -q "$WB_ROOT/repos/$FAKE"
    git -C "$WB_ROOT/repos/$FAKE" remote add origin "git@github.com:owner/$FAKE.git"
}

teardown() {
    rm -rf "$WB_ROOT/repos/$FAKE"
}

@test "repos clone marks origin as the gh default base repo" {
    # The per-repo step clone runs to make `gh pr checkout` non-interactive
    run just repos _set-default "$FAKE"
    [ "$status" -eq 0 ]
    resolved=$(git -C "$WB_ROOT/repos/$FAKE" config --get remote.origin.gh-resolved)
    [ "$resolved" = "base" ]
}

@test "repos _set-default is idempotent" {
    just repos _set-default "$FAKE"
    run just repos _set-default "$FAKE"
    [ "$status" -eq 0 ]
    resolved=$(git -C "$WB_ROOT/repos/$FAKE" config --get remote.origin.gh-resolved)
    [ "$resolved" = "base" ]
}
