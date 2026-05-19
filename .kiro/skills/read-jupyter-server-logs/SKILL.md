---
name: read-jupyter-server-logs
description: Read Jupyter Server logs from a running server's terminal output in cmux. Use when you need to check for errors, debug server issues, or see what happened in the last N seconds.
---

# Read Jupyter Server Logs

Read logs from a running Jupyter Server by capturing the terminal output of the surface it's running in.

## Prerequisites

- A Jupyter Server running in a cmux terminal surface (started via `just start-server` or `just start-server`)

## Finding the Server Surface

The server runs in a terminal surface. Find it by listing surfaces and looking for the one running `just start-server`:

```bash
cmux list-pane-surfaces --workspace <workspace-ref> --json
# Look for a surface with title containing "just start-server"
```

Or if you know the workspace:

```bash
cmux list-pane-surfaces --workspace workspace:3 --json | jq -r '.surfaces[] | "\(.ref) \(.title)"'
```

## Reading Logs

### Last N lines

```bash
cmux read-screen --workspace <ws> --surface <surface> --lines 50
```

`--lines` reads from the bottom (most recent). Implies `--scrollback`.

### Full scrollback

```bash
cmux read-screen --workspace <ws> --surface <surface> --scrollback
```

### Count total lines

```bash
cmux read-screen --workspace <ws> --surface <surface> --scrollback | wc -l
```

## Logs Since N Seconds Ago

The server logs use the format `[LEVEL YYYY-MM-DD HH:MM:SS.mmm Module]`. Use lexicographic comparison on the timestamp:

```bash
SINCE=$(date -v-${N}S '+%Y-%m-%d %H:%M:%S')
cmux read-screen --workspace <ws> --surface <surface> --scrollback | \
  awk -v since="$SINCE" '/^\[/ { ts=substr($0, 4, 19); if (ts >= since) found=1 } found'
```

Examples:
```bash
# Last 30 seconds
SINCE=$(date -v-30S '+%Y-%m-%d %H:%M:%S')

# Last 5 minutes
SINCE=$(date -v-5M '+%Y-%m-%d %H:%M:%S')
```

## Filtering Logs

Pipe through standard shell tools:

```bash
# Errors only
cmux read-screen --workspace <ws> --surface <surface> --scrollback | grep -i "error\|traceback"

# Specific endpoint
cmux read-screen ... --scrollback | grep "POST /api/ai"

# Context around an error (5 lines before, 10 after)
cmux read-screen ... --scrollback | grep -B5 -A10 "500 "

# Count errors
cmux read-screen ... --scrollback | grep -c "\[E "

# Startup logs (first 50 lines)
cmux read-screen ... --scrollback | head -50
```

## Log Levels

| Prefix | Meaning |
|--------|---------|
| `[D ...]` | Debug |
| `[I ...]` | Info |
| `[W ...]` | Warning |
| `[E ...]` | Error |

## Tips

- If the scrollback is very long (>500 lines), prefer `--lines 50` or time-based filtering over reading everything.
- Lines without a `[` prefix are continuation lines (tracebacks, request headers, JSON bodies) — they belong to the preceding log entry.
- The server also logs non-bracketed lines from uvicorn (e.g., `INFO: ::1:51042 - "GET /mcp HTTP/1.1" 200 OK`).
