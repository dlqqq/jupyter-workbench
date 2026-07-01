#!/usr/bin/env bash
# Tests for `just workbench verify`.
#
# Hermetic: every case runs with --offline so the SSH + gh-auth network checks
# become SKIP rows and never touch GitHub.

load helpers

setup() {
    wb_setup
}

teardown() {
    wb_teardown
}

@test "verify --offline passes on a provisioned box (exit 0)" {
    run just workbench verify --offline
    [ "$status" -eq 0 ]
    # network checks must be skipped, not run
    echo "$output" | grep -q "gh-auth        skipped (offline)"
    echo "$output" | grep -q "github-ssh     skipped (offline)"
    # summary line asserts overall pass
    echo "$output" | grep -qE "All checks passed|with optional warnings"
}

@test "WORKBENCH_VERIFY_OFFLINE env var also enables offline mode" {
    WORKBENCH_VERIFY_OFFLINE=1 run just workbench verify
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "offline mode: network checks skipped"
    echo "$output" | grep -q "github-ssh     skipped (offline)"
}

@test "verify reports the required tools and config rows" {
    run just workbench verify --offline
    [ "$status" -eq 0 ]
    for tool in git just uv gh jq; do
        echo "$output" | grep -qE "REQ ${tool}\b"
    done
    echo "$output" | grep -q "repos.json"
    echo "$output" | grep -q "agent-cmd"
}

@test "missing git identity fails a required check (exit 1)" {
    # Shadow git with a wrapper that reports user.name/user.email as unset and
    # passes everything else (including the --path-format rev-parse the module
    # backtick needs) through to the real git. This is platform-independent:
    # env-var config overrides (GIT_CONFIG_GLOBAL/SYSTEM) don't blank a *local*
    # repo identity, which CI sets, so we intercept the lookup itself.
    sandbox="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$sandbox"
    real_git=$(command -v git)
    cat >"$sandbox/git" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == "config" && "\$*" == *"--get user.name"* ]]; then exit 1; fi
if [[ "\$1" == "config" && "\$*" == *"--get user.email"* ]]; then exit 1; fi
exec "$real_git" "\$@"
EOF
    chmod +x "$sandbox/git"
    PATH="$sandbox:$PATH" run just workbench verify --offline
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "git-identity   unset"
    echo "$output" | grep -q "Required checks failed"
}

# NOTE: the recipe's `git rev-parse --path-format` capability probe is not unit
# tested. It is effectively unreachable: the module-level `wb := \`git rev-parse
# --path-format=absolute ...\`` backtick runs the same command at parse time, so
# any git lacking --path-format fails workbench-root resolution before the recipe
# body (and its probe) ever runs. The probe stays in the recipe as defense in
# depth, but it can't fail through the recipe, so there is nothing to assert.

@test "missing required tool fails (exit 1) via a sandbox PATH" {
    # Build a sandbox bin/ with every tool the recipe needs EXCEPT uv, then run
    # with PATH pointed only at it. Simulates a real "uv not installed" box
    # without disturbing the outer environment.
    sandbox="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$sandbox"
    for t in env sh bash git just gh jq grep head xargs dirname sed cat python3; do
        p=$(command -v "$t" 2>/dev/null) && ln -s "$p" "$sandbox/$t"
    done
    PATH="$sandbox" run just workbench verify --offline
    [ "$status" -eq 1 ]
    # ANSI color codes sit between FAIL and REQ, so match on the row's detail text.
    echo "$output" | grep -qE "REQ uv +not found"
    echo "$output" | grep -q "Required checks failed"
}
