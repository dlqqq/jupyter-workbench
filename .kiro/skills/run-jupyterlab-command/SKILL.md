---
name: run-jupyterlab-command
description: Execute JupyterLab commands programmatically via the browser console. Use when you need to trigger registered commands (open chat, send message, toggle panel, etc.) without clicking through the UI.
---

# Run JupyterLab Commands

Execute any registered JupyterLab command programmatically through `cmux browser eval`.

## Prerequisites

The server must be started with `--expose-app-in-browser` to expose the app on `window.jupyterapp`:

```bash
just server-start
```

If the server is already running without this flag, run `just server-restart`.

## Executing a Command

```bash
SURFACE=$(just get-browser-surface)

cmux browser $SURFACE eval "
window.jupyterapp.commands.execute('command-id', {
  arg1: 'value1',
  arg2: 'value2'
}).then(function() { window.__result = 'success'; }).catch(function(e) { window.__result = 'error: ' + e.message; });
'started'
"

# Check result (promises don't return directly)
sleep 2
cmux browser $SURFACE eval "window.__result || 'pending'"
```

## Important Notes

- `cmux browser eval` only returns string results. Non-string returns (booleans, numbers, objects) will timeout. Always return a string literal or wrap in `String(...)`.
- Promises don't resolve inline — fire the command, store the result on `window`, then read it in a follow-up eval.
- Always end your eval script with a string literal (e.g., `'started'`) so it doesn't timeout.

## Listing Available Commands

```bash
cmux browser $SURFACE eval "window.jupyterapp.commands.listCommands().join('\n')"
```

## Example: Open a Chat with a Pre-filled Message

```bash
cmux browser $SURFACE eval "
window.jupyterapp.commands.execute('jupyterlab-chat:openWithMessage', {
  name: 'my-chat',
  inSidePanel: false,
  input: 'Hello world',
  autoSend: false
}).then(function() { window.__result = 'success'; }).catch(function(e) { window.__result = 'error: ' + e.message; });
'started'
"
sleep 2
cmux browser $SURFACE eval "window.__result || 'pending'"
```

## Example: Send a Message Automatically

```bash
cmux browser $SURFACE eval "
window.jupyterapp.commands.execute('jupyterlab-chat:openWithMessage', {
  name: 'my-chat',
  inSidePanel: true,
  input: '@Kiro hello',
  autoSend: true
}).then(function() { window.__result = 'sent'; }).catch(function(e) { window.__result = 'error: ' + e.message; });
'started'
"
sleep 2
cmux browser $SURFACE eval "window.__result || 'pending'"
```
