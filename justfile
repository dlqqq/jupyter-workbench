set dotenv-load := true

alias addws := add-workspace
alias rmws := remove-workspaces
alias addwt := add-worktree
alias rmwt := remove-worktree
alias list := list-recipes
# Echo the workbench root directory
[group('workbench')]
get-workbench-root:
    @echo "{{ justfile_directory() }}"

# List all available recipes
[group('workbench')]
list-recipes:
    @just --list --list-heading=""

# Create a new workspace (non-blocking: setup runs in the new cmux workspace)
[group('workbench')]
[arg("name", help="workspace name")]
[arg("dev", long, help="comma-separated repos to dev-install")]
[arg("with_pkgs", long="with", help="comma-separated PyPI packages to add")]
[arg("spawn_agent", long="spawn-agent", value="true")]
[arg("prompt", long, help="agent prompt (requires --spawn-agent)")]
add-workspace name dev="" with_pkgs="" spawn_agent="false" prompt="":
    #!/usr/bin/env bash
    set -eo pipefail
    wb_root="{{ justfile_directory() }}"
    cd "$wb_root"

    name="{{ name }}"
    IFS=',' read -ra dev_repos <<< "{{ dev }}"
    IFS=',' read -ra with_pkgs <<< "{{ with_pkgs }}"

    # Remove empty elements from empty defaults
    [[ -z "${dev_repos[0]}" ]] && dev_repos=()
    [[ -z "${with_pkgs[0]}" ]] && with_pkgs=()

    # Validate dev repo names (strip #pr suffix for lookup)
    for repo in "${dev_repos[@]}"; do
        repo_name="${repo%%#*}"
        url=$(jq -r --arg r "$repo_name" '.[$r].url // empty' "$wb_root/repos.json")
        if [[ -z "$url" ]]; then
            echo "Error: '$repo_name' not found in repos.json" >&2
            echo "Available repos: $(jq -r 'keys[]' "$wb_root/repos.json" | tr '\n' ' ')" >&2
            exit 1
        fi
    done

    ws="$wb_root/workspaces/$name"
    if [[ -d "$ws" ]]; then
        echo "Error: workspace '$name' already exists at $ws" >&2
        exit 1
    fi

    # Create workspace directory
    mkdir -p "$ws"
    cp "$wb_root/workspaces/templates/"* "$ws/"

    # Symlink workspace justfile and skills to workbench root
    ln -sf "$wb_root/workspace.just" "$ws/justfile"
    mkdir -p "$ws/.kiro"
    ln -sf "$wb_root/.kiro/skills" "$ws/.kiro/skills"
    [[ -f "$wb_root/.env" ]] && cp "$wb_root/.env" "$ws/.env"

    # Write workspace info with dev-repos as object
    repos_obj="{}"
    for repo in "${dev_repos[@]}"; do
        repo_name="${repo%%#*}"
        pr_number="${repo#*#}"
        [[ "$pr_number" == "$repo" ]] && pr_number=""
        if [[ -n "$pr_number" ]]; then
            repos_obj=$(echo "$repos_obj" | jq --arg r "$repo_name" --argjson pr "$pr_number" '.[$r] = {"pr-number": $pr}')
        else
            repos_obj=$(echo "$repos_obj" | jq --arg r "$repo_name" '.[$r] = {}')
        fi
    done
    prompt="{{ prompt }}"
    jq -n --argjson repos "$repos_obj" --arg prompt "$prompt" \
        '{"dev-repos": $repos, "prompt": $prompt, "server": null, "browser": null}' \
        > "$ws/.workspace_info.json"

    # Build command to run in the new workspace
    if [[ "{{ spawn_agent }}" == "true" ]]; then
        cmd="just setup-workspace && just spawn-agent"
    else
        cmd="just setup-workspace && cmux notify --title 'Setup done: $name' --body 'Ready'"
    fi

    cmux_ws=$(cmux new-workspace --name "[ws] $name" --cwd "$ws" --command "$cmd")
    echo "✓ Workspace '$name' created at: $ws"
    echo "✓ Setup running in cmux workspace: $cmux_ws"

# Remove workspaces (comma-separated, or --all, or --except)
[group('workbench')]
[arg("names", help="comma-separated workspace names (ignored with --all)")]
[arg("all", long, value="true")]
[arg("except", long="except", short="x", help="remove all EXCEPT these comma-separated names")]
remove-workspaces names="" all="false" except="":
    #!/usr/bin/env bash
    set -eo pipefail
    wb_root="{{ justfile_directory() }}"

    if [[ -n "{{ except }}" && -n "{{ names }}" ]]; then
        echo "Error: --except cannot be used with a names list. Use --except alone to remove all except the listed items." >&2
        exit 1
    fi
    if [[ -n "{{ except }}" && "{{ all }}" == "true" ]]; then
        echo "Error: --except cannot be used with --all." >&2
        exit 1
    fi

    # Build the list of workspaces to remove
    targets=()
    if [[ -n "{{ except }}" ]]; then
        IFS=',' read -ra keep_list <<< "{{ except }}"
        for ws in "$wb_root"/workspaces/*/; do
            [[ -d "$ws" ]] || continue
            name=$(basename "$ws")
            [[ "$name" == "templates" ]] && continue
            skip=false
            for keep in "${keep_list[@]}"; do
                [[ "$name" == "$keep" ]] && skip=true && break
            done
            [[ "$skip" == "false" ]] && targets+=("$name")
        done
    elif [[ "{{ all }}" == "true" ]]; then
        for ws in "$wb_root"/workspaces/*/; do
            [[ -d "$ws" ]] || continue
            name=$(basename "$ws")
            [[ "$name" == "templates" ]] && continue
            targets+=("$name")
        done
    else
        if [[ -z "{{ names }}" ]]; then
            echo "Usage: just remove-workspaces <names> | --all | --except <names>" >&2
            exit 1
        fi
        IFS=',' read -ra targets <<< "{{ names }}"
    fi

    for name in "${targets[@]}"; do
        just _remove-workspace-one "$name"
    done

[private]
_remove-workspace-one name:
    #!/usr/bin/env bash
    set -eo pipefail
    wb_root="{{ justfile_directory() }}"
    ws="$wb_root/workspaces/{{ name }}"
    if [[ ! -d "$ws" ]]; then
        echo "Error: workspace '{{ name }}' not found" >&2
        exit 1
    fi
    pgid=$(jq -r '.server.pgid // empty' "$ws/.workspace_info.json" 2>/dev/null)
    if [[ -n "$pgid" ]]; then
        kill -TERM -- -"$pgid" 2>/dev/null || true
    fi
    rm -rf "$ws"
    echo "✓ Removed workspace '{{ name }}'"



# Create a workbench worktree (for modifying workbench infrastructure)
[group('workbench')]
[arg("name", help="worktree/branch name")]
add-worktree name:
    #!/usr/bin/env bash
    set -eo pipefail
    wb_root="{{ justfile_directory() }}"
    wt="$wb_root/worktrees/{{ name }}"
    if [[ -d "$wt" ]]; then
        echo "Error: worktree '{{ name }}' already exists" >&2
        exit 1
    fi
    mkdir -p "$wb_root/worktrees"
    git worktree add -b "{{ name }}" "$wt"
    cmux_ws=$(cmux new-workspace --name "[wt] {{ name }}" --cwd "$wt")
    echo "✓ Worktree '{{ name }}' ready at: $wt"
    echo "✓ cmux workspace ready: $cmux_ws"
    echo "  cd $wt"

# Remove workbench worktrees (comma-separated, or --except)
[group('workbench')]
[arg("names", help="comma-separated worktree names")]
[arg("force", long, value="true")]
[arg("except", long="except", short="x", help="remove all EXCEPT these comma-separated names")]
remove-worktree names="" force="false" except="":
    #!/usr/bin/env bash
    set -eo pipefail
    wb_root="{{ justfile_directory() }}"

    if [[ -n "{{ except }}" && -n "{{ names }}" ]]; then
        echo "Error: --except cannot be used with a names list. Use --except alone to remove all except the listed items." >&2
        exit 1
    fi

    # Build the list of worktrees to remove
    targets=()
    if [[ -n "{{ except }}" ]]; then
        IFS=',' read -ra keep_list <<< "{{ except }}"
        for wt in "$wb_root"/worktrees/*/; do
            [[ -d "$wt" ]] || continue
            name=$(basename "$wt")
            skip=false
            for keep in "${keep_list[@]}"; do
                [[ "$name" == "$keep" ]] && skip=true && break
            done
            [[ "$skip" == "false" ]] && targets+=("$name")
        done
    else
        if [[ -z "{{ names }}" ]]; then
            echo "Usage: just remove-worktree <names> | --except <names>" >&2
            exit 1
        fi
        IFS=',' read -ra targets <<< "{{ names }}"
    fi

    for name in "${targets[@]}"; do
        just _remove-worktree-one "$name" "{{ force }}"
    done

[private]
_remove-worktree-one name force="false":
    #!/usr/bin/env bash
    set -eo pipefail
    wb_root="{{ justfile_directory() }}"
    wt="$wb_root/worktrees/{{ name }}"
    if [[ ! -d "$wt" ]]; then
        echo "Error: worktree '{{ name }}' not found" >&2
        exit 1
    fi
    if [[ "{{ force }}" != "true" ]]; then
        if [[ -n "$(git -C "$wt" status --porcelain)" ]]; then
            echo "Error: worktree '{{ name }}' has uncommitted changes. Use --force to override." >&2
            exit 1
        fi
        if ! git merge-base --is-ancestor "{{ name }}" main; then
            echo "Error: branch '{{ name }}' has unmerged commits. Push and merge first, or use --force." >&2
            exit 1
        fi
    fi
    git worktree remove "$wt" --force
    git branch -D "{{ name }}" 2>/dev/null || true
    echo "✓ Removed worktree '{{ name }}'"
