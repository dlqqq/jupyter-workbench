# Resolve the workbench root (main worktree) from anywhere in the repo tree
wb := `git rev-parse --path-format=absolute --git-common-dir | xargs dirname`

# Merge a workbench PR (squash + delete remote branch), then update root main
[no-cd]
[group('workbench')]
[arg("pr", help="PR number to merge")]
merge pr:
    #!/usr/bin/env bash
    set -eo pipefail
    wb="{{ wb }}"
    pr="{{ pr }}"

    # Resolve the remote `main` tracks (fallback: first remote) and the repo slug
    remote=$(git -C "$wb" config branch.main.remote 2>/dev/null || true)
    [[ -z "$remote" ]] && remote=$(git -C "$wb" remote | head -1)
    repo=$(git -C "$wb" remote get-url "$remote" | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')

    # Capture the PR's head branch before merging (for local cleanup)
    headref=$(gh pr view "$pr" --repo "$repo" --json headRefName -q .headRefName 2>/dev/null || true)
    if [[ -z "$headref" ]]; then
        echo "Aborting: PR #$pr not found in $repo." >&2
        exit 1
    fi

    echo "Merging PR #$pr ($headref) into $repo (squash)..."
    gh pr merge "$pr" --repo "$repo" --squash --delete-branch

    # Update the root worktree's local main (it's checked out there, so we
    # fast-forward it in place). Warn but continue if it can't (decision: keep
    # the merge even if local main can't be updated cleanly).
    git -C "$wb" fetch "$remote"
    if git -C "$wb" merge --ff-only "$remote/main" >/dev/null 2>&1; then
        echo "✓ Root main updated to $(git -C "$wb" rev-parse --short main)"
    else
        echo -e "\033[1;33mWarning: could not fast-forward root main (dirty or diverged).\033[0m" >&2
        echo "  Update it manually: git -C $wb merge --ff-only $remote/main" >&2
    fi

    # Best-effort delete the local branch. Skipped automatically if it's checked
    # out in a workspace worktree — 'just ws rebase' cleans that case up.
    if git -C "$wb" branch -D "$headref" >/dev/null 2>&1; then
        echo "✓ Deleted local branch '$headref'"
    fi

    echo "✓ Merged PR #$pr"

# Verify workbench prerequisites (tools, auth, config). Pass --offline to skip network checks.
[no-cd]
[group('workbench')]
verify offline="":
    #!/usr/bin/env bash
    set -uo pipefail   # NOT -e: every check must run and report

    wb="{{ wb }}"
    # `offline` is a plain optional positional so `verify --offline` works: just's
    # [arg] attribute has no boolean-flag form, and any non-empty value (e.g. the
    # literal "--offline") enables offline mode. WORKBENCH_VERIFY_OFFLINE also sets it.
    offline="{{ offline }}"
    [[ -n "${WORKBENCH_VERIFY_OFFLINE:-}" ]] && offline="1"

    fail=0   # required-check failures → nonzero exit
    warn=0

    # --- output helper -----------------------------------------------------
    # row LEVEL(REQ/OPT) STATUS(OK/FAIL/WARN/SKIP) NAME DETAIL HINT
    row() {
        local level="$1" status="$2" name="$3" detail="$4" hint="$5"
        local color reset='\033[0m'
        case "$status" in
            OK)   color='\033[0;32m' ;;
            FAIL) color='\033[0;31m' ;;
            WARN) color='\033[0;33m' ;;
            SKIP) color='\033[0;36m' ;;
            *)    color='' ;;
        esac
        printf "  ${color}%-4s${reset} %-3s %-14s %s\n" "$status" "$level" "$name" "$detail"
        if [[ "$status" != "OK" && "$status" != "SKIP" && -n "$hint" ]]; then
            printf "        -> %s\n" "$hint"
        fi
        [[ "$status" == "FAIL" ]] && fail=1
        [[ "$status" == "WARN" ]] && warn=1
        return 0
    }

    # first dotted-numeric token from a version string
    extract_ver() { grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' <<<"$1" | head -1; }

    # verlte A B -> true if A <= B (dotted numeric compare, pads to 3 fields)
    verlte() {
        local IFS=. ; local -a a b
        read -ra a <<<"$1"; read -ra b <<<"$2"
        for i in 0 1 2; do
            local x=${a[i]:-0} y=${b[i]:-0}
            ((10#$x < 10#$y)) && return 0
            ((10#$x > 10#$y)) && return 1
        done
        return 0
    }

    # presence-only required tool (prints version if available)
    check_req() {
        local name="$1" hint="$2"
        if ! command -v "$name" >/dev/null 2>&1; then
            row REQ FAIL "$name" "not found" "$hint"; return
        fi
        # --version is multi-line for some tools (e.g. gh); head -1 keeps the
        # first line so extract_ver picks the tool's own version.
        local got; got=$(extract_ver "$("$name" --version 2>&1 | head -1)")
        row REQ OK "$name" "${got:-present}" ""
    }
    # optional tool: a miss is WARN, not FAIL
    check_opt() {
        local name="$1" hint="$2"
        if ! command -v "$name" >/dev/null 2>&1; then
            row OPT WARN "$name" "not found" "$hint"; return
        fi
        local got; got=$(extract_ver "$("$name" --version 2>&1 | head -1)")
        row OPT OK "$name" "${got:-present}" ""
    }

    echo "Jupyter Workbench - prerequisite check"
    [[ -n "$offline" ]] && echo "(offline mode: network checks skipped)"
    echo ""
    echo "Tools:"

    # git: presence + capability probe for the --path-format idiom the recipes use
    if ! command -v git >/dev/null 2>&1; then
        row REQ FAIL git "not found" "install git"
    else
        gitver=$(extract_ver "$(git --version 2>&1)")
        if git rev-parse --path-format=absolute --git-common-dir >/dev/null 2>&1; then
            row REQ OK git "${gitver:-present}" ""
        else
            row REQ FAIL git "${gitver:-present} (no --path-format)" \
                "upgrade git; recipes need 'git rev-parse --path-format=absolute'"
        fi
    fi

    check_req just "install just: https://github.com/casey/just"
    check_req uv   "install uv: https://github.com/astral-sh/uv"
    check_req gh   "install gh: https://cli.github.com"

    # jq: presence required; soft 1.6 version warning only
    if ! command -v jq >/dev/null 2>&1; then
        row REQ FAIL jq "not found" "install jq: https://jqlang.github.io/jq/"
    else
        jqver=$(extract_ver "$(jq --version 2>&1)")
        if [[ -n "$jqver" ]] && ! verlte 1.6 "$jqver"; then
            row REQ WARN jq "$jqver (want >= 1.6)" "upgrade jq"
        else
            row REQ OK jq "${jqver:-present}" ""
        fi
    fi

    echo ""
    echo "Optional / auto-managed:"

    # Python: optional (uv can download one). Warn only if present + out of range.
    if command -v python3 >/dev/null 2>&1; then
        pv=$(python3 -c 'import sys;print("%d.%d"%sys.version_info[:2])' 2>/dev/null || true)
        if [[ -n "$pv" ]] && verlte 3.10 "$pv" && verlte "$pv" 3.13; then
            row OPT OK python3 "$pv" ""
        else
            row OPT WARN python3 "${pv:-unknown} (venv wants 3.10-3.13)" \
                "uv downloads a compatible Python automatically if needed"
        fi
    else
        row OPT OK python3 "absent (uv-managed)" ""
    fi

    check_opt cmux "needed to auto-launch agents + (deprecated) server/browser; macOS-oriented"
    check_opt bats "needed only to run 'just workbench-tests run-all'"

    echo ""
    echo "Auth & access:"

    # gh login (not offline-safe: keyring/network). Skipped in offline mode.
    if [[ -n "$offline" ]]; then
        row REQ SKIP gh-auth "skipped (offline)" ""
    elif ! command -v gh >/dev/null 2>&1; then
        row REQ FAIL gh-auth "gh missing" "install gh, then gh auth login"
    elif gh auth status >/dev/null 2>&1; then
        row REQ OK gh-auth "logged in" ""
    else
        row REQ FAIL gh-auth "not logged in" "run: gh auth login"
    fi

    # GitHub SSH: repos.json uses git@github.com URLs. ssh -T exits 1 on SUCCESS,
    # so match the success string; BatchMode avoids any prompt/hang.
    if [[ -n "$offline" ]]; then
        row REQ SKIP github-ssh "skipped (offline)" ""
    elif ! command -v ssh >/dev/null 2>&1; then
        row REQ FAIL github-ssh "ssh not found" "install OpenSSH"
    else
        ssh_out=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
                      -o ConnectTimeout=8 -T git@github.com 2>&1)
        if grep -qi "successfully authenticated" <<<"$ssh_out"; then
            row REQ OK github-ssh "authenticated" ""
        elif grep -qi "permission denied" <<<"$ssh_out"; then
            row REQ FAIL github-ssh "permission denied" \
                "add an SSH key to GitHub: https://docs.github.com/authentication"
        else
            # network error / timeout / unknown -> WARN, not FAIL (offline tolerance)
            row REQ WARN github-ssh "unreachable" "check network or run: ssh -T git@github.com"
        fi
    fi

    # git identity
    gname=$(git config --get user.name 2>/dev/null || true)
    gemail=$(git config --get user.email 2>/dev/null || true)
    if [[ -n "$gname" && -n "$gemail" ]]; then
        row REQ OK git-identity "$gname <$gemail>" ""
    else
        row REQ FAIL git-identity "unset" "git config --global user.name / user.email"
    fi

    echo ""
    echo "Config:"

    # Guard: are we actually at a workbench root? {{ wb }} resolves via git; if
    # repos.json isn't there, config checks would be meaningless.
    if [[ ! -f "$wb/repos.json" ]]; then
        row REQ FAIL workbench-root "no repos.json at $wb" \
            "run 'just workbench verify' from inside the jupyter-workbench repo"
    else
        if jq -e . "$wb/repos.json" >/dev/null 2>&1; then
            row REQ OK repos.json "valid JSON" ""
        else
            row REQ FAIL repos.json "invalid JSON" "fix $wb/repos.json"
        fi
    fi

    # workbench-config.json -> agent-cmd (key REQ; CLI-on-PATH WARN)
    if agent_cmd=$(jq -re '."agent-cmd"' "$wb/workbench-config.json" 2>/dev/null); then
        acmd=${agent_cmd%% *}
        if command -v "$acmd" >/dev/null 2>&1; then
            row OPT OK agent-cmd "$acmd (found)" ""
        else
            row OPT WARN agent-cmd "$acmd not on PATH" \
                "install '$acmd' or set agent-cmd in workbench-config.json to a CLI you have"
        fi
    else
        row REQ FAIL agent-cmd "missing in workbench-config.json" \
            "add \"agent-cmd\", e.g. \"claude --permission-mode auto\""
    fi

    echo ""
    if [[ "$fail" -ne 0 ]]; then
        printf "\033[0;31mX Required checks failed. Fix the items above and re-run.\033[0m\n"
        exit 1
    elif [[ "$warn" -ne 0 ]]; then
        printf "\033[0;33mOK Required checks passed (with optional warnings).\033[0m\n"
        exit 0
    else
        printf "\033[0;32mOK All checks passed.\033[0m\n"
        exit 0
    fi
