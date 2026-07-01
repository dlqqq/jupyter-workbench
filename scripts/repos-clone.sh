#!/usr/bin/env bash
# Parallel clone/fetch of every repo in repos.json, with a live status board.
#
# Usage: repos-clone.sh <workbench-root>
# Env:
#   REPOS_CLONE_JOBS      max concurrent git ops         (default: 8)
#   REPOS_CLONE_FORCE_TTY 1 = render as if stdout is a TTY (test seam; default: off)
#
# Exit: 0 if all repos ready; 1 if >=1 repo failed (names + git stderr on stderr).
set -o pipefail
set -m   # own process group per background job -> clean grandchild (git) teardown

root="${1:?usage: repos-clone.sh <workbench-root>}"
repos_json="$root/repos.json"
mkdir -p "$root/repos"

# --- concurrency limit (flat default; network-bound, not CPU-bound) -----------
MAX_JOBS="${REPOS_CLONE_JOBS:-8}"
[[ "$MAX_JOBS" =~ ^[0-9]+$ && "$MAX_JOBS" -ge 1 ]] || MAX_JOBS=1

# --- TTY detection (with test override) ---------------------------------------
IS_TTY=0
if [[ "${REPOS_CLONE_FORCE_TTY:-0}" == "1" ]]; then IS_TTY=1
elif [[ -t 1 ]]; then IS_TTY=1; fi

# --- scratch dir + trap state (initialize BEFORE trap so cleanup is safe) -----
STATUS_DIR="$(mktemp -d "${TMPDIR:-/tmp}/repos-clone.XXXXXX")"
WORKER_PIDS=()
RENDER_PID=""

cleanup() {
    # Kill each worker's whole process group (kills the in-flight git too).
    local pid
    for pid in "${WORKER_PIDS[@]:-}"; do
        [[ -n "$pid" ]] && kill -TERM -- -"$pid" 2>/dev/null
    done
    [[ -n "$RENDER_PID" ]] && kill "$RENDER_PID" 2>/dev/null
    [[ "$IS_TTY" -eq 1 ]] && tput cnorm 2>/dev/null
    rm -rf "$STATUS_DIR" 2>/dev/null
    return 0
}
trap cleanup EXIT INT TERM

# --- read repo list (name TAB url), preserve file order -----------------------
names=(); urls=()
while IFS=$'\t' read -r name url; do
    names+=("$name"); urls+=("$url")
done < <(jq -r 'to_entries[] | "\(.key)\t\(.value.url)"' "$repos_json")
n=${#names[@]}

# --- atomic status write (renderer never sees a partial line) -----------------
set_status() {  # $1=index  $2=text
    printf '%s\n' "$2" > "$STATUS_DIR/$1.tmp" && mv "$STATUS_DIR/$1.tmp" "$STATUS_DIR/$1"
}

# --- per-repo worker (returns 0 always; failure is recorded, not propagated) --
work() {
    local idx="$1" name="$2" url="$3"
    local dir="$root/repos/$name"
    local errf="$STATUS_DIR/$idx.err"
    if [[ -d "$dir/.git" || ( -d "$dir" && -f "$dir/HEAD" ) ]]; then
        # existing repo -> fetch
        [[ "$IS_TTY" -eq 0 ]] && echo "⟳ $name: fetching…"
        set_status "$idx" "fetching"
        local up before after count
        up=$(git -C "$dir" rev-parse --abbrev-ref '@{u}' 2>/dev/null || echo "origin/HEAD")
        before=$(git -C "$dir" rev-parse "$up" 2>/dev/null || echo "")
        if git -C "$dir" fetch --prune origin >/dev/null 2>"$errf"; then
            after=$(git -C "$dir" rev-parse "$up" 2>/dev/null || echo "")
            if [[ -n "$before" && -n "$after" ]]; then
                count=$(git -C "$dir" rev-list --count "$before..$after" 2>/dev/null || echo 0)
            else
                count=0
            fi
            git -C "$dir" config remote.origin.gh-resolved base   # gh default base repo
            set_status "$idx" "done +$count"
            [[ "$IS_TTY" -eq 0 ]] && echo "✓ $name: fetched (+$count)"
        else
            set_status "$idx" "failed fetch"
            [[ "$IS_TTY" -eq 0 ]] && echo "✗ $name: fetch failed"
        fi
    elif [[ -d "$dir" ]]; then
        # dir exists but is not a git repo (interrupted prior clone) -> flag it
        set_status "$idx" "failed not-a-git-repo"
        echo "$dir exists but is not a git repository" > "$errf"
        [[ "$IS_TTY" -eq 0 ]] && echo "✗ $name: not a git repo (remove $dir and retry)"
    else
        # missing -> clone
        [[ "$IS_TTY" -eq 0 ]] && echo "⬇ $name: cloning…"
        set_status "$idx" "cloning"
        if git clone "$url" "$dir" >/dev/null 2>"$errf"; then
            git -C "$dir" config remote.origin.gh-resolved base   # gh default base repo
            set_status "$idx" "done cloned"
            [[ "$IS_TTY" -eq 0 ]] && echo "✓ $name: cloned"
        else
            set_status "$idx" "failed clone"
            [[ "$IS_TTY" -eq 0 ]] && echo "✗ $name: clone failed"
        fi
    fi
    return 0
}

# --- render loop (TTY only) ---------------------------------------------------
render() {
    local first=1 i nm state cols line
    cols=$(tput cols 2>/dev/null || echo 80)
    while :; do
        if [[ "$first" -eq 1 ]]; then
            for ((i=0;i<n;i++)); do echo; done   # reserve n lines
            first=0
        fi
        tput cuu "$n" 2>/dev/null
        for ((i=0;i<n;i++)); do
            nm="${names[$i]}"
            state=$(cat "$STATUS_DIR/$i" 2>/dev/null || echo "queued")
            tput el 2>/dev/null                    # clear to end of line
            line=$(printf '  %-34s %s' "$nm" "$state")
            printf '%s\n' "${line:0:$cols}"        # clamp to width -> no wrap corruption
        done
        [[ -f "$STATUS_DIR/.stop" ]] && break
        sleep 0.2
    done
}

# --- launch renderer (skip entirely when n==0) --------------------------------
if [[ "$IS_TTY" -eq 1 && "$n" -gt 0 ]]; then
    tput civis 2>/dev/null
    render & RENDER_PID=$!
fi

# --- launch bounded pool (FIFO throttle; bash-3.2-safe, no `wait -n`) ---------
for ((i=0;i<n;i++)); do
    set_status "$i" "queued"
    work "$i" "${names[$i]}" "${urls[$i]}" &
    WORKER_PIDS+=($!)
    if [[ "${#WORKER_PIDS[@]}" -ge "$MAX_JOBS" ]]; then
        wait "${WORKER_PIDS[0]}" 2>/dev/null   # reap oldest (caps at N, not a perfect pool)
        WORKER_PIDS=("${WORKER_PIDS[@]:1}")
    fi
done
# Wait ONLY on the remaining workers — a bare `wait` would also block on the
# renderer background job, which doesn't exit until `.stop` is written below.
for pid in "${WORKER_PIDS[@]:-}"; do
    [[ -n "$pid" ]] && wait "$pid" 2>/dev/null
done

# --- stop renderer + final draw -----------------------------------------------
if [[ -n "$RENDER_PID" ]]; then
    : > "$STATUS_DIR/.stop"
    wait "$RENDER_PID" 2>/dev/null
    tput cnorm 2>/dev/null
fi

# --- failure summary + exit code ----------------------------------------------
failed=()
for ((i=0;i<n;i++)); do
    st=$(cat "$STATUS_DIR/$i" 2>/dev/null || echo "")
    if [[ "$st" == failed* ]]; then
        failed+=("${names[$i]}")
        echo "✗ ${names[$i]}: $st" >&2
        if [[ -s "$STATUS_DIR/$i.err" ]]; then
            tail -n 3 "$STATUS_DIR/$i.err" | sed 's/^/    /' >&2
        fi
    fi
done
if [[ "${#failed[@]}" -gt 0 ]]; then
    echo "✗ ${#failed[@]}/$n repo(s) failed: ${failed[*]}" >&2
    exit 1
fi
echo "✓ All $n repos ready"
