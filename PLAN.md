# PR Checkout Support in add-workspace and add-dev

## Goal

Allow specifying a PR number when adding a dev repo, e.g.:

```bash
just add-workspace my-feature --dev=jupyter-ai-acp-client#119
just add-dev jupyter-ai-acp-client#119
```

## Behavior

When a repo is specified as `<repo>#<pr-number>`:

1. Clone the repo normally (origin = upstream)
2. Use `gh pr checkout <pr-number>` to check out the PR branch
3. Add a remote named after the PR author's GitHub username, pointing to their fork
   - Get the author's username and fork URL via: `gh pr view <pr-number> --json headRepositoryOwner,headRepository`
   - Add remote: `git remote add <username> <fork-url>`
4. The working branch should be the PR's head branch

## Example

For PR #119 authored by "aieroshe" on jupyter-ai-acp-client:

```
origin  → git@github.com:jupyter-ai-contrib/jupyter-ai-acp-client.git
aieroshe → git@github.com:aieroshe/jupyter-ai-acp-client.git
```

Working branch: whatever branch the PR is on.

## Files to modify

- `justfile` — update `add-workspace` to parse `repo#pr` syntax
- `workspace.just` — update `add-dev` to parse `repo#pr` syntax
- Shared logic: extract PR number, clone, checkout PR, add author remote

## Testing

1. Create a test workspace with a real PR: `just add-workspace test --dev=jupyter-ai-acp-client#119`
2. Verify remotes are correct: `cd workspaces/test/jupyter-ai-acp-client && git remote -v`
3. Verify the PR branch is checked out: `git branch --show-current`
4. Clean up: `just remove-workspaces test`

## Rules

- Commit to the `pr-checkout` branch
- Open a PR with `gh pr create` when done
- Notify the user if stuck or when complete
