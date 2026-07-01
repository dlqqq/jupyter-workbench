#!/usr/bin/env bash
# Tests for `just repos clone` (scripts/repos-clone.sh).
#
# Hermetic: every test builds a throwaway workbench root via mktemp -d with its
# own repos/ + repos.json pointing at local `file://` bare remotes, so no network
# is hit and the real repos.json is never touched. The script is invoked by its
# absolute path in the real workbench (WB_ROOT/scripts/repos-clone.sh) against the
# temp root passed as $1.

load helpers

SCRIPT="$WB_ROOT/scripts/repos-clone.sh"
TEMP_ROOTS=()

setup() {
    wb_setup
    TEMP_ROOTS=()
}

teardown() {
    local r
    for r in "${TEMP_ROOTS[@]:-}"; do
        [[ -n "$r" && -d "$r" ]] && rm -rf "$r"
    done
    return 0
}

# Build a throwaway workbench root with an empty repos/ dir.
mk_temp_root() {                     # echoes the temp root path
    local troot; troot="$(mktemp -d "${TMPDIR:-/tmp}/rc-test.XXXXXX")"
    mkdir -p "$troot/repos" "$troot/remotes"
    TEMP_ROOTS+=("$troot")
    echo "$troot"
}

# Create $root/remotes/$name.git — a bare remote with one commit on main.
mk_bare_remote() {                   # $1=root $2=name
    local root="$1" name="$2" work; work="$(mktemp -d)"
    git init -q "$work"
    git -C "$work" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
    git init -q --bare "$root/remotes/$name.git"
    git -C "$work" push -q "$root/remotes/$name.git" HEAD:refs/heads/main
    # Point the bare remote's HEAD at main so clones check it out regardless of
    # the runner's init.defaultBranch (CI often defaults to master).
    git -C "$root/remotes/$name.git" symbolic-ref HEAD refs/heads/main
    rm -rf "$work"
}

# Push one more empty commit onto a bare remote's main.
push_commit_to_remote() {            # $1=root $2=name
    local root="$1" name="$2" work; work="$(mktemp -d)"
    git clone -q "$root/remotes/$name.git" "$work"
    git -C "$work" -c user.email=t@t -c user.name=t commit -q --allow-empty -m more
    git -C "$work" push -q origin HEAD:refs/heads/main
    rm -rf "$work"
}

# Write $root/repos.json from name=url pairs.
write_repos_json() {                 # $1=root, remaining args: name=url pairs
    local root="$1"; shift
    local jqargs=() prog='{}' i=0 kv
    for kv in "$@"; do
        jqargs+=(--arg "n$i" "${kv%%=*}" --arg "u$i" "${kv#*=}")
        prog="$prog | .[\$n$i] = {url: \$u$i}"; i=$((i+1))
    done
    jq -n "${jqargs[@]}" "$prog" > "$root/repos.json"
}

@test "clones a missing repo and marks origin as gh default base repo" {
    root="$(mk_temp_root)"
    mk_bare_remote "$root" foo
    write_repos_json "$root" "foo=file://$root/remotes/foo.git"

    run bash "$SCRIPT" "$root"
    [ "$status" -eq 0 ]
    [ -d "$root/repos/foo/.git" ]
    resolved=$(git -C "$root/repos/foo" config --get remote.origin.gh-resolved)
    [ "$resolved" = "base" ]
    [[ "$output" == *"foo"* ]]
}

@test "counts new commits pulled on fetch" {
    root="$(mk_temp_root)"
    mk_bare_remote "$root" foo
    write_repos_json "$root" "foo=file://$root/remotes/foo.git"
    run bash "$SCRIPT" "$root"
    [ "$status" -eq 0 ]

    push_commit_to_remote "$root" foo
    run bash "$SCRIPT" "$root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"+1"* ]]
}

@test "fetch fast-forwards the local checked-out branch to origin" {
    root="$(mk_temp_root)"
    mk_bare_remote "$root" foo
    write_repos_json "$root" "foo=file://$root/remotes/foo.git"
    run bash "$SCRIPT" "$root"
    [ "$status" -eq 0 ]

    push_commit_to_remote "$root" foo
    run bash "$SCRIPT" "$root"
    [ "$status" -eq 0 ]
    # the local branch — not just origin/main — must now point at the new commit
    local head origin
    head=$(git -C "$root/repos/foo" rev-parse HEAD)
    origin=$(git -C "$root/repos/foo" rev-parse origin/main)
    [ "$head" = "$origin" ]
}

@test "fetch with no new commits reports +0" {
    root="$(mk_temp_root)"
    mk_bare_remote "$root" foo
    write_repos_json "$root" "foo=file://$root/remotes/foo.git"
    run bash "$SCRIPT" "$root"
    [ "$status" -eq 0 ]

    run bash "$SCRIPT" "$root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"+0"* ]]
}

@test "error isolation: bad repo fails, good repo still clones, non-zero exit" {
    root="$(mk_temp_root)"
    mk_bare_remote "$root" good
    write_repos_json "$root" \
        "good=file://$root/remotes/good.git" \
        "bad=file:///nonexistent/bad.git"

    run bash "$SCRIPT" "$root"
    [ "$status" -eq 1 ]
    # the good repo still cloned + got its gh-resolved config
    [ -d "$root/repos/good/.git" ]
    resolved=$(git -C "$root/repos/good" config --get remote.origin.gh-resolved)
    [ "$resolved" = "base" ]
    # failure summary names the bad repo
    [[ "$output" == *"bad"* ]]
}

@test "REPOS_CLONE_JOBS=1 serial fallback works" {
    root="$(mk_temp_root)"
    mk_bare_remote "$root" foo
    write_repos_json "$root" "foo=file://$root/remotes/foo.git"

    run env REPOS_CLONE_JOBS=1 bash "$SCRIPT" "$root"
    [ "$status" -eq 0 ]
    [ -d "$root/repos/foo/.git" ]
}

@test "dir exists but is not a git repo -> failure with guidance" {
    root="$(mk_temp_root)"
    mk_bare_remote "$root" foo
    write_repos_json "$root" "foo=file://$root/remotes/foo.git"
    mkdir -p "$root/repos/foo"
    touch "$root/repos/foo/stray.txt"

    run bash "$SCRIPT" "$root"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not a git repo"* ]]
}

@test "dangling symlink at repos/<name> is replaced by a fresh clone" {
    root="$(mk_temp_root)"
    mk_bare_remote "$root" foo
    write_repos_json "$root" "foo=file://$root/remotes/foo.git"
    # Simulate a workspace repos/ symlink whose shared target was deleted.
    ln -s "$root/nonexistent-target" "$root/repos/foo"
    [ -L "$root/repos/foo" ] && [ ! -e "$root/repos/foo" ]  # dangling

    run bash "$SCRIPT" "$root"
    [ "$status" -eq 0 ]
    [ -d "$root/repos/foo/.git" ]
}

@test "empty repos.json reports all 0 repos ready" {
    root="$(mk_temp_root)"
    echo '{}' > "$root/repos.json"

    run bash "$SCRIPT" "$root"
    [ "$status" -eq 0 ]
    [[ "$output" == *"All 0 repos ready"* ]]
}

@test "TTY render path smoke (REPOS_CLONE_FORCE_TTY=1)" {
    root="$(mk_temp_root)"
    mk_bare_remote "$root" foo
    write_repos_json "$root" "foo=file://$root/remotes/foo.git"

    run env REPOS_CLONE_FORCE_TTY=1 bash "$SCRIPT" "$root"
    [ "$status" -eq 0 ]
    [ -d "$root/repos/foo/.git" ]
}
