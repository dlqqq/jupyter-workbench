---
name: jupyter-chat-browser-use
description: Interact with Jupyter Chat in a cmux browser surface. Use when you need to create chats, send messages, mention AI personas, or read chat history through the JupyterLab browser UI.
---

# Jupyter Chat Browser Use

Automate Jupyter Chat interactions through a cmux browser surface running JupyterLab.

## Prerequisites

- A JupyterLab server running in the worktree (`just start` or `just start-cmux`)
- A cmux browser surface open to JupyterLab
- The `jupyter-chat` extension enabled

## Finding the Browser Surface

```bash
# Get the browser surface ref in the current workspace
SURFACE=$(just get-browser-surface)
```

## Important: WKWebView Quirks

cmux uses WKWebView. Two commands are needed to interact with MUI components:
- `type` inserts text but does NOT fire keyboard events
- `press` fires keyboard events but does NOT insert text

For components like MUI Autocomplete that need both (e.g., the `@` mention popup), use `type` followed by `press`.

## Actions

### Create a New Chat

```bash
# Snapshot to find the launcher button
cmux browser $SURFACE snapshot --interactive
# Look for: button "Create a chat and open it" [ref=eN]

# Click it
cmux browser $SURFACE click <launcher-button-ref>

# A dialog appears with a textbox and Ok/Cancel buttons
# Snapshot again to get the dialog refs
cmux browser $SURFACE snapshot --interactive
# Look for: textbox "untitled" [ref=eN], button "Ok" [ref=eN]

# Name the chat and confirm
cmux browser $SURFACE fill <textbox-ref> "my-chat-name"
cmux browser $SURFACE click <ok-ref>
```

### Open the Chat Sidebar Panel

```bash
cmux browser $SURFACE snapshot --interactive
# Look for: tab "Jupyter Chat" [ref=eN]
cmux browser $SURFACE click <jupyter-chat-tab-ref>
```

### Type a Message with @mention

The chat input selector is `.jp-chat-input-textfield textarea` (or find it via snapshot as a `combobox` element).

```bash
# Get a snapshot ref for the chat input
cmux browser $SURFACE snapshot --interactive --selector ".jp-chat-input-textfield"
# Returns: combobox [ref=eN]

# Clear, focus, then type @ (need both type + press for autocomplete to trigger)
cmux browser $SURFACE fill <ref> ""
cmux browser $SURFACE click <ref>
cmux browser $SURFACE type <ref> "@"
cmux browser $SURFACE press "@"

# Wait briefly for the autocomplete menu to appear, then read options:
cmux browser $SURFACE eval "
const listbox = document.querySelector('.MuiAutocomplete-listbox');
listbox ? [...listbox.children].map(o => o.textContent.trim()).join('\n') : 'no listbox';
"

# Navigate with arrow keys to select a persona
cmux browser $SURFACE press ArrowDown   # repeat to reach desired persona
cmux browser $SURFACE press Enter       # select it

# Type the message
cmux browser $SURFACE type <ref> "your message here"
```

### Send a Message

```bash
cmux browser $SURFACE press Enter
```

### List Available Personas (from UI)

Trigger the `@` autocomplete and read the options:

```bash
cmux browser $SURFACE fill <ref> ""
cmux browser $SURFACE click <ref>
cmux browser $SURFACE type <ref> "@"
cmux browser $SURFACE press "@"
sleep 0.5
cmux browser $SURFACE eval "
const listbox = document.querySelector('.MuiAutocomplete-listbox');
[...listbox.children].map(o => o.textContent.trim()).join('\n');
"
# Close the menu without selecting
cmux browser $SURFACE press Escape
```

### Read Chat Messages

Read the `.chat` file directly from disk (most reliable):

```bash
cat <worktree>/<filename>.chat | jq '.messages[] | {sender: .sender, body: .body}'
```

Or get all message bodies:

```bash
cat <worktree>/<filename>.chat | jq -r '.messages[].body'
```

### List Chat Files

```bash
ls <worktree>/*.chat
```

### Read File Browser Contents

The file browser items aren't exposed as interactive elements. Use eval:

```bash
cmux browser $SURFACE eval "document.querySelector('.jp-DirListing-content')?.innerText"
```

## Persona Name to Arrow Key Count

Options are shown in alphabetical order. The first option is selected by default.

| Persona | ArrowDown presses |
|---------|-------------------|
| Claude | 0 (selected by default) |
| Codex | 1 |
| Copilot | 2 |
| Gemini | 3 |
| Goose | 4 |
| Kiro | 5 |
| OpenCode | 6 |

Note: This order may change if personas are added/removed. Always verify by reading the listbox options.

## Vision: Screenshots

Some UI states aren't fully captured by DOM queries or the `.chat` file. Use screenshots to see what's happening.

```bash
# Save a screenshot to the worktree
mkdir -p screenshots
cmux browser $SURFACE screenshot --out screenshots/$(date +%s).png
```

Then read the screenshot with the image read tool.

### When to Use Screenshots

- Check the current state of the chat when you don't understand what is going on
- Check if the agent is still writing
- Check for visual errors
- Confirmation that an action worked

## Approving Tool Calls

Agents may request tool call approval (e.g., creating a file). This shows as a diff with Yes/Always/No buttons. These buttons are NOT visible in `snapshot --interactive` but can be found via CSS selectors.

### Selectors

| Action | Selector |
|--------|----------|
| Allow once | `.jp-jupyter-ai-acp-client-permission-btn-allow-once` |
| Allow always | `.jp-jupyter-ai-acp-client-permission-btn-allow-always` |
| Reject | `.jp-jupyter-ai-acp-client-permission-btn-reject-once` |

### Approve a tool call

```bash
# Click "Yes" (allow once)
cmux browser $SURFACE eval "document.querySelector('.jp-jupyter-ai-acp-client-permission-btn-allow-once')?.click()"

# Click "Always" (allow always)
cmux browser $SURFACE eval "document.querySelector('.jp-jupyter-ai-acp-client-permission-btn-allow-always')?.click()"

# Click "No" (reject)
cmux browser $SURFACE eval "document.querySelector('.jp-jupyter-ai-acp-client-permission-btn-reject-once')?.click()"
```

### Check if a tool call is pending

```bash
cmux browser $SURFACE eval "
const btn = document.querySelector('.jp-jupyter-ai-acp-client-permission-btn');
btn ? 'pending' : 'none';
"
```

## Full Example: Send a Message to Kiro

```bash
SURFACE=$(just get-browser-surface)

# Open chat sidebar and select a chat
cmux browser $SURFACE snapshot --interactive
cmux browser $SURFACE click <jupyter-chat-tab-ref>
cmux browser $SURFACE click <chat-tab-ref>

# Get input ref
cmux browser $SURFACE snapshot --interactive --selector ".jp-chat-input-textfield"

# Type @Kiro hello
cmux browser $SURFACE fill <ref> ""
cmux browser $SURFACE click <ref>
cmux browser $SURFACE type <ref> "@"
cmux browser $SURFACE press "@"
sleep 0.5
cmux browser $SURFACE press ArrowDown   # 5 times for Kiro
cmux browser $SURFACE press ArrowDown
cmux browser $SURFACE press ArrowDown
cmux browser $SURFACE press ArrowDown
cmux browser $SURFACE press ArrowDown
cmux browser $SURFACE press Enter       # select Kiro
cmux browser $SURFACE type <ref> "hello"
cmux browser $SURFACE press Enter       # send

# Read the response from disk
sleep 3
cat <worktree>/*.chat | jq -r '.messages[-1].body'
```
