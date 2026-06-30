set dotenv-load := true

root := justfile_directory()

mod repos
mod dev
mod ws 'workspaces'
mod server
mod browser
mod workbench-tests

alias list := list-recipes
alias restart := server::restart

# List all available recipes
list-recipes:
    @just --list --list-heading=""

# Start server and open browser
start: server::start browser::open

# Alias for `uv sync`
sync *args:
    uv sync

# Add packages via uv (comma-separated)
add pkgs:
    #!/usr/bin/env bash
    set -eo pipefail
    IFS=',' read -ra packages <<< "{{ pkgs }}"
    uv add "${packages[@]}"

# Show which repos are dev-installed in this workspace (scans ./dev)
status:
    #!/usr/bin/env bash
    set -eo pipefail
    echo "Dev-installed repos:"
    for d in "{{ root }}"/dev/*/; do
        [[ -d "$d" ]] || continue
        echo "  $(basename "$d")"
    done

# Spawn an agent session with the given prompt
spawn-agent prompt="":
    #!/usr/bin/env bash
    set -eo pipefail
    root="{{ root }}"
    pgid=$(ps -o pgid= -p $$ | tr -d ' ')
    jq --arg pgid "$pgid" '.agent = {"pgid": ($pgid | tonumber)}' \
        "$root/.workspace_info.json" > "$root/.workspace_info.json.tmp" \
        && mv "$root/.workspace_info.json.tmp" "$root/.workspace_info.json"
    source "$root/.venv/bin/activate"
    exec kiro-cli chat --agent dlq -a {{ quote(prompt) }}

# Stop the agent session
stop-agent:
    #!/usr/bin/env bash
    set -eo pipefail
    root="{{ root }}"

    agent_pgid=$(jq -r '.agent.pgid // empty' "$root/.workspace_info.json")
    if [[ -z "$agent_pgid" ]]; then
        echo "Error: no agent is running in this workspace." >&2
        exit 1
    fi

    echo "Stopping agent..."
    kill -TERM -- -"$agent_pgid" 2>/dev/null || true

    for i in {1..12}; do
        if ! kill -0 -- -"$agent_pgid" 2>/dev/null; then
            jq '.agent = null' "$root/.workspace_info.json" > "$root/.workspace_info.json.tmp" \
                && mv "$root/.workspace_info.json.tmp" "$root/.workspace_info.json"
            echo "✓ Agent stopped"
            exit 0
        fi
        sleep 0.25
    done

    echo "Agent didn't stop within 3s, force killing..."
    kill -9 -- -"$agent_pgid" 2>/dev/null || true
    jq '.agent = null' "$root/.workspace_info.json" > "$root/.workspace_info.json.tmp" \
        && mv "$root/.workspace_info.json.tmp" "$root/.workspace_info.json"
    echo "✓ Agent force killed"

# Merge this workspace's PR, then reset the worktree to a fresh branch off main
[group('workspace')]
land:
    #!/usr/bin/env bash
    set -eo pipefail
    root="{{ root }}"
    cd "$root"

    # 1. Refuse if there are uncommitted tracked changes (untracked files survive
    #    the branch switch, so they don't block — but we list them as an FYI).
    dirty=$(git status --porcelain --untracked-files=no)
    if [[ -n "$dirty" ]]; then
        echo -e "\033[1;31mAborting: this worktree has uncommitted changes.\033[0m" >&2
        echo "$dirty" >&2
        echo "" >&2
        echo "Commit, stash, or discard them, then run 'just land' again." >&2
        exit 1
    fi
    untracked=$(git status --porcelain --untracked-files=normal | grep '^??' || true)
    [[ -n "$untracked" ]] && echo -e "\033[1;33mNote: untracked files (preserved across the reset):\033[0m\n$untracked\n"

    # 2. Resolve the remote (the one `main` tracks), repo slug, and current branch.
    remote=$(git config branch.main.remote 2>/dev/null || true)
    [[ -z "$remote" ]] && remote=$(git remote | head -1)
    repo=$(git remote get-url "$remote" | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')
    oldbranch=$(git rev-parse --abbrev-ref HEAD)

    # 3. Confirm a PR exists for this branch, then squash-merge it.
    if ! gh pr view "$oldbranch" --repo "$repo" --json number >/dev/null 2>&1; then
        echo "Aborting: no open PR found for branch '$oldbranch' in $repo." >&2
        exit 1
    fi
    echo "Merging PR for '$oldbranch' into $repo (squash)..."
    gh pr merge "$oldbranch" --repo "$repo" --squash --delete-branch

    # 4. Pull the merged main into the shared store.
    git fetch "$remote"

    # 5. Reset this worktree onto a fresh dated branch off the updated main.
    wsname=$(basename "$root")
    newbranch="$(date +%Y%m%d)-$wsname"
    if git show-ref --verify --quiet "refs/heads/$newbranch"; then
        newbranch="$newbranch-$(date +%H%M%S)"
    fi
    git switch -c "$newbranch" "$remote/main"

    # 6. Delete the old merged branch (we're no longer on it).
    git branch -D "$oldbranch" 2>/dev/null || true

    echo "✓ Merged and deleted '$oldbranch'"
    echo "✓ Worktree reset onto '$newbranch' (off $remote/main)"

# Close this workspace (stop agent + server, close cmux workspace)
close:
    #!/usr/bin/env bash
    set -eo pipefail
    root="{{ root }}"

    agent_pgid=$(jq -r '.agent.pgid // empty' "$root/.workspace_info.json")
    if [[ -n "$agent_pgid" ]] && kill -0 -- -"$agent_pgid" 2>/dev/null; then
        just stop-agent
    fi

    server_pgid=$(jq -r '.server.pgid // empty' "$root/.workspace_info.json")
    if [[ -n "$server_pgid" ]] && kill -0 -- -"$server_pgid" 2>/dev/null; then
        just server stop
    fi

    cmux close-workspace --workspace "${CMUX_WORKSPACE_ID}"
