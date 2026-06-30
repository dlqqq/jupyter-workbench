root := justfile_directory()

# Print the browser surface ref
surface:
    @jq -r '.browser.surface_id // empty' "{{ root }}/.workspace_info.json"

# Open a browser to JupyterLab
open:
    #!/usr/bin/env bash
    set -eo pipefail
    root="{{ root }}"

    existing=$(jq -r '.browser.surface_id // empty' "$root/.workspace_info.json")
    if [[ -n "$existing" ]]; then
        echo "Error: A browser is already open. Use 'just browser refresh' or 'just browser close' first." >&2
        exit 1
    fi

    url=$(jq -r '.server.url // empty' "$root/.workspace_info.json")
    token=$(jq -r '.server.token // empty' "$root/.workspace_info.json")
    if [[ -z "$url" || -z "$token" ]]; then
        echo "Error: no server is running. Use 'just server start' first." >&2
        exit 1
    fi

    browser_json=$(cmux --json browser open "${url}lab?token=${token}" --workspace "${CMUX_WORKSPACE_ID}")
    browser_surface=$(echo "$browser_json" | jq -r '.surface_ref')
    jq --arg sid "$browser_surface" '.browser = {"surface_id": $sid}' \
        "$root/.workspace_info.json" > "$root/.workspace_info.json.tmp" \
        && mv "$root/.workspace_info.json.tmp" "$root/.workspace_info.json"

    echo "✓ Browser opened: $browser_surface"

# Reload the browser
refresh:
    #!/usr/bin/env bash
    set -eo pipefail
    root="{{ root }}"
    surface=$(jq -r '.browser.surface_id // empty' "$root/.workspace_info.json")
    if [[ -z "$surface" ]]; then
        echo "Error: no browser is open. Use 'just browser open' first." >&2
        exit 1
    fi
    cmux browser "$surface" reload
    echo "✓ Browser reloaded"

# Close the browser
close:
    #!/usr/bin/env bash
    set -eo pipefail
    root="{{ root }}"
    surface=$(jq -r '.browser.surface_id // empty' "$root/.workspace_info.json")
    if [[ -z "$surface" ]]; then
        echo "Error: no browser is open." >&2
        exit 1
    fi
    cmux close-surface --surface "$surface"
    jq '.browser = null' "$root/.workspace_info.json" > "$root/.workspace_info.json.tmp" \
        && mv "$root/.workspace_info.json.tmp" "$root/.workspace_info.json"
    echo "✓ Browser closed"

# Run a JS script in the browser (scripts live in scripts/)
eval script *args:
    #!/usr/bin/env bash
    set -eo pipefail
    root="{{ root }}"
    surface=$(jq -r '.browser.surface_id // empty' "$root/.workspace_info.json")
    if [[ -z "$surface" ]]; then
        echo "Error: no browser is open. Use 'just browser open' first." >&2
        exit 1
    fi

    script_path="$root/scripts/{{ script }}.js"
    if [[ ! -f "$script_path" ]]; then
        echo "Error: script not found: $script_path" >&2
        exit 1
    fi

    encoded_args=""
    for arg in {{ args }}; do
        json_arg=$(printf '%s' "$arg" | jq -Rs .)
        if [[ -n "$encoded_args" ]]; then
            encoded_args="$encoded_args, $json_arg"
        else
            encoded_args="$json_arg"
        fi
    done

    fn=$(cat "$script_path")
    wrapped="($fn)($encoded_args)"

    result=$(cmux browser "$surface" eval "$wrapped")
    if [[ "$result" == ERROR:* ]]; then
        echo "$result" >&2
        exit 1
    fi
    echo "$result"
