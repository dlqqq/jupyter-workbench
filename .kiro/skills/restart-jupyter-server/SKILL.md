---
name: restart-jupyter-server
description: Restart a Jupyter Server running in a cmux terminal. Use when you need to restart the server after code changes, extension updates, or to recover from a hung state.
---

# Restart Jupyter Server

Kill and restart a Jupyter Server running in a cmux terminal surface. Works in both bash and zsh.

## When to Restart

Only needed after making **backend changes** (`.py` files). Frontend changes (TypeScript/CSS) only require `just build` — the browser will pick them up on reload without a server restart.

## Prerequisites

- A Jupyter Server running in a known terminal surface (started via `just start`)

## Finding the Server Surface

```bash
cmux list-pane-surfaces --workspace <workspace-ref> --json | jq -r '.surfaces[] | "\(.ref) \(.title)"'
# Look for the surface running "just start"
```

## Restart Procedure

All commands are sent to the server's terminal surface via `cmux send` and `cmux send-key`.

### Step 1: Suspend the server

```bash
cmux send-key --workspace <ws> --surface <surface> ctrl+z
```

Wait ~1 second for the shell to regain control. The shell will print `[1]+ Stopped ...`.

### Step 2: Get the PID and kill the process group (graceful)

```bash
cmux send --workspace <ws> --surface <surface> "pid=\$(jobs -l %1 | awk '{print \$3}'); kill -TERM -- -\$pid\n"
```

This gets the PID of the suspended job and sends SIGTERM to its entire process group (negative PID = process group). Works in both bash and zsh.

Wait ~3 seconds for graceful shutdown.

### Step 3: Verify it died

```bash
cmux read-screen --workspace <ws> --surface <surface> --lines 3
```

Look for `killed` or `terminated` in the output. If you see it, proceed to restart.

### Step 4: Force kill (only if Step 3 shows the process is still alive)

Only send this if the server didn't die from SIGTERM:

```bash
cmux send --workspace <ws> --surface <surface> "kill -9 -- -\$pid\n"
```

### Step 5: Restart

```bash
cmux send --workspace <ws> --surface <surface> "just start --no-browser\n"
```

## Full Sequence

```bash
WS="workspace:3"
SURFACE="surface:19"

# Suspend
cmux send-key --workspace $WS --surface $SURFACE ctrl+z
sleep 1

# Kill process group (graceful)
cmux send --workspace $WS --surface $SURFACE "pid=\$(jobs -l %1 | awk '{print \$3}'); kill -TERM -- -\$pid\n"
sleep 3

# Check if it died
cmux read-screen --workspace $WS --surface $SURFACE --lines 3
# If output shows "killed" or "terminated" -> proceed to restart
# If NOT dead -> force kill:
#   cmux send --workspace $WS --surface $SURFACE "kill -9 -- -\$pid\n"
#   sleep 1

# Restart
cmux send --workspace $WS --surface $SURFACE "just start --no-browser\n"
```

## Verifying the Server Restarted

```bash
# Wait for the server to come up
sleep 5

# Check if it's running
cmux read-screen --workspace $WS --surface $SURFACE --lines 5
# Should show startup messages like "Jupyter Server is running at..."
```

## Notes

- `jobs -p %1` works in both bash and zsh
- `kill -- -$pid` sends to the process group (all child processes), not just the lead process
- The server may spawn child processes (kernels, MCP servers) — killing the process group ensures they all die
- If the terminal has multiple suspended jobs, `%1` refers to the most recently suspended one
