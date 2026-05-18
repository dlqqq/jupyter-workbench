set dotenv-load := true
set fallback

repo_root := justfile_directory()
repo_name := file_name(justfile_directory())

# List all available recipes (including worktree and workbench)
[group('repo')]
list-recipes:
    #!/usr/bin/env bash
    wt_root=$(just get-worktree-root)
    (cd "$(cd "$wt_root" && just get-workbench-root)" && just --list --list-heading="")
    echo ""
    (cd "$wt_root" && just --list --list-heading="")
    echo ""
    just --list --list-heading=""

# Run `jlpm` (JupyterLab's bundled version of `yarn`), forwarding given arguments
[group('repo')]
jlpm *args:
    #!/usr/bin/env bash
    set -eo pipefail
    wt_root=$(just get-worktree-root)
    uv run --project "$wt_root" jlpm {{ args }}

# Run `pytest` on a repo, forwarding given arguments
[group('repo')]
pytest *args:
    #!/usr/bin/env bash
    set -eo pipefail
    wt_root=$(just get-worktree-root)
    uv run --project "$wt_root" pytest {{ args }}

# Run `mypy` on a repo, forwarding given arguments
[group('repo')]
mypy *args:
    #!/usr/bin/env bash
    set -eo pipefail
    wt_root=$(just get-worktree-root)
    uv run --project "$wt_root" mypy {{ args }}

# Run frontend linters
[group('repo')]
lint:
    #!/usr/bin/env bash
    set -eo pipefail
    wt_root=$(just get-worktree-root)
    uv run --project "$wt_root" jlpm lint
    uv run --project "$wt_root" jlpm lint

# Rebuild frontend for the current repo
[group('repo')]
build:
    #!/usr/bin/env bash
    set -eo pipefail
    wt_root=$(just get-worktree-root)
    uv run --project "$wt_root" jlpm build

# Enable all extensions for this repo
[group('repo')]
enable-repo-extensions:
    just enable-repo-server-extensions
    just enable-repo-lab-extensions

# Enable server extension(s) for this repo
[group('repo')]
enable-repo-server-extensions:
    #!/usr/bin/env bash
    set -eo pipefail
    wt_root=$(just get-worktree-root)
    repo_name="{{ repo_name }}"
    pkg_names=$(jq -r --arg r "$repo_name" '
        .[$r].packages // [{"name": ($r | gsub("-";"_"))}]
        | .[].name
    ' "$wt_root/repos.json")
    while IFS= read -r pkg_name; do
        [[ -n "$pkg_name" ]] || continue
        echo "Enabling server extension: $pkg_name"
        uv run --project "$wt_root" jupyter server extension enable "$pkg_name"
    done <<< "$pkg_names"

# Enable lab extension(s) for this repo
[group('repo')]
enable-repo-lab-extensions:
    #!/usr/bin/env bash
    set -eo pipefail
    wt_root=$(just get-worktree-root)
    repo_root="{{ repo_root }}"
    repo_name="{{ repo_name }}"
    pkg_parents=$(jq -r --arg r "$repo_name" '
        .[$r].packages // [{"parentDir": "."}]
        | .[].parentDir
    ' "$wt_root/repos.json")
    while IFS= read -r parent_dir; do
        [[ -n "$parent_dir" ]] || continue
        echo "Enabling lab extension in: $repo_name/$parent_dir"
        (cd "$repo_root/$parent_dir" && uv run --project "$wt_root" jupyter labextension develop . --overwrite) || true
    done <<< "$pkg_parents"

# Ensure a fork exists and is set as a remote
[group('repo')]
ensure-fork:
    #!/usr/bin/env bash
    set -eo pipefail
    cd "{{ repo_root }}"
    if ! git remote get-url fork &>/dev/null; then
        echo "Forking..."
        gh repo fork --remote --remote-name fork
        gh repo set-default "$(git remote get-url origin | sed 's|.*github.com[:/]||;s|\.git$||')"
    else
        echo "Fork remote already exists"
    fi
