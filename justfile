set dotenv-load := true

alias addws := add-workspace
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

# Delete all workspaces and worktrees not currently open in cmux
[group('workbench')]
cleanup:
    #!/usr/bin/env bash
    set -eo pipefail
    wb_root="{{ justfile_directory() }}"

    # Get names of open cmux workspaces/worktrees
    open_ws=()
    open_wt=()
    while IFS= read -r title; do
        if [[ "$title" == "[ws] "* ]]; then
            open_ws+=("${title#\[ws\] }")
        elif [[ "$title" == "[wt] "* ]]; then
            open_wt+=("${title#\[wt\] }")
        fi
    done < <(cmux list-workspaces --json | jq -r '.workspaces[].title')

    # Find workspaces not open in cmux
    ws_to_delete=()
    for ws in "$wb_root"/workspaces/*/; do
        [[ -d "$ws" ]] || continue
        name=$(basename "$ws")
        [[ "$name" == "templates" ]] && continue
        found=false
        for open in "${open_ws[@]}"; do
            [[ "$name" == "$open" ]] && found=true && break
        done
        [[ "$found" == "false" ]] && ws_to_delete+=("$name")
    done

    # Find worktrees not open in cmux
    wt_to_delete=()
    for wt in "$wb_root"/worktrees/*/; do
        [[ -d "$wt" ]] || continue
        name=$(basename "$wt")
        found=false
        for open in "${open_wt[@]}"; do
            [[ "$name" == "$open" ]] && found=true && break
        done
        [[ "$found" == "false" ]] && wt_to_delete+=("$name")
    done

    if [[ ${#ws_to_delete[@]} -eq 0 && ${#wt_to_delete[@]} -eq 0 ]]; then
        echo "Nothing to clean up."
        exit 0
    fi

    echo -e "\033[1;33mWARNING: This will delete all worktrees and workspaces not currently open in cmux.\033[0m"
    echo ""

    if [[ ${#wt_to_delete[@]} -gt 0 ]]; then
        echo "Worktrees to delete:"
        for name in "${wt_to_delete[@]}"; do
            echo "├── $name"
        done
        echo ""
    fi

    if [[ ${#ws_to_delete[@]} -gt 0 ]]; then
        echo "Workspaces to delete:"
        for name in "${ws_to_delete[@]}"; do
            echo "├── $name"
        done
        echo ""
    fi

    read -p "Continue? [y/N] " answer
    if [[ ! "$answer" =~ ^[Yy] ]]; then
        echo "Cancelled."
        exit 0
    fi

    # Run deletion in a background terminal tab
    pane=$(cmux identify --json | jq -r '.caller.pane_ref')
    surface_json=$(cmux new-surface --workspace "${CMUX_WORKSPACE_ID}" --pane "$pane" --focus false --json)
    surface=$(echo "$surface_json" | jq -r '.surface_ref')

    # Build the deletion script
    script="cd $wb_root"
    for name in "${wt_to_delete[@]}"; do
        script="$script && (git worktree remove '$wb_root/worktrees/$name' --force 2>/dev/null || rm -rf '$wb_root/worktrees/$name') && git branch -D '$name' 2>/dev/null; echo '✓ Removed worktree $name'"
    done
    for name in "${ws_to_delete[@]}"; do
        script="$script && { pgid=\$(jq -r '.server.pgid // empty' '$wb_root/workspaces/$name/.workspace_info.json' 2>/dev/null); [[ -n \"\$pgid\" ]] && kill -TERM -- -\"\$pgid\" 2>/dev/null || true; rm -rf '$wb_root/workspaces/$name'; echo '✓ Removed workspace $name'; }"
    done
    script="$script && cmux close-surface --surface $surface"

    cmux send --workspace "${CMUX_WORKSPACE_ID}" --surface "$surface" "$script\n"
    echo "✓ Cleanup starting in background tab. Tab will close itself once complete."

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
