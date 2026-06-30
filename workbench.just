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
