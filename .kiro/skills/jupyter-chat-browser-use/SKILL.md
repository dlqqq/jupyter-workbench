---
name: jupyter-chat-browser-use
description: Interact with Jupyter Chat in a cmux browser surface. Use when you need to create chats, send messages, mention AI personas, or read chat history through the JupyterLab browser UI.
---

# Jupyter Chat Browser Use

Automate Jupyter Chat interactions through workspace recipes and cmux browser commands.

## Prerequisites

- A JupyterLab server running (`just start-server`)
- A browser open (`just open-browser`)
- The `jupyter-chat` extension installed (`just add-dev jupyter-chat`)

## Recipes

Use these `just` recipes for common chat operations:

```bash
# List all chats
just list-chats

# Open a new chat (side panel by default)
just open-chat
just open-chat --mainarea

# Send a message to a named chat
just send-chat-message <chat-name> "<message>"

# Read all messages from a chat (returns JSON)
just read-chat-messages <chat-name>
```

## Browser Surface

```bash
SURFACE=$(just get-browser-surface)
```

## Sending Messages

The `send-chat-message` recipe uses cmux browser commands to click the input, type, and click send:

```bash
just send-chat-message chat-1779330823 "hello world"
```

Under the hood:
1. Clicks the textarea: `#jupyter-chat\:\:widget\:\:<name>\.chat textarea`
2. Types the message: `cmux browser $SURFACE type --selector "..." --text "..."`
3. Clicks send: `button[aria-label*='Send message' i]`

## Reading Messages

`just read-chat-messages <chat-name>` returns JSON with structured content:

```json
[
  {
    "sender": "self",
    "time": "10:07 AM",
    "content": [
      { "type": "text", "value": "hello" },
      { "type": "code", "value": "print('hi')\n", "toolbarButtons": ["...selector..."] },
      { "type": "math-block", "value": "x+y=z" }
    ],
    "toolCalls": []
  },
  {
    "sender": "Kiro",
    "time": "10:07 AM",
    "content": [],
    "toolCalls": [
      {
        "status": "in_progress",
        "summary": "• Creating hello.py",
        "files": ["hello.py"],
        "lines": ["+ print(\"hello\")"],
        "permissionButtons": [
          { "label": "Yes", "selector": "#... .jp-jupyter-ai-acp-client-permission-btn-allow-once:not([disabled])" },
          { "label": "Always", "selector": "#... .jp-jupyter-ai-acp-client-permission-btn-allow-always:not([disabled])" },
          { "label": "No", "selector": "#... .jp-jupyter-ai-acp-client-permission-btn-reject-once:not([disabled])" }
        ]
      }
    ]
  }
]
```

Content types: `text`, `code`, `math-inline`, `math-block`.

## Approving Tool Calls

Click the permission button selector from `read-chat-messages` output:

```bash
cmux browser $SURFACE click --selector '<selector from permissionButtons>'
```

Or use the class directly:

```bash
cmux browser $SURFACE click --selector '.jp-jupyter-ai-acp-client-permission-btn-allow-once:not([disabled])'
```

## Browser Eval Scripts

The `browser-eval` recipe runs JS scripts from `scripts/`:

```bash
just browser-eval <script-name> [args...]
```

Scripts are IIFEs that take string arguments. The recipe JSON-encodes args and checks for `ERROR:` prefix in the return value.

Available scripts:
- `open-chat-sidepanel` — opens a chat in the side panel
- `open-chat-mainarea` — opens a chat in the main area
- `list-chats` — lists chat files via the contents API
- `read-chat-messages` — reads messages from the DOM

## @Mentions

To mention an AI persona, type `@` in the chat input. The autocomplete popup appears with available personas. Use arrow keys to select and Enter to confirm.

```bash
# Type @ to trigger autocomplete
cmux browser $SURFACE type --selector "<textarea-selector>" "@"

# Read available options
cmux browser $SURFACE eval "
const listbox = document.querySelector('.MuiAutocomplete-listbox');
listbox ? [...listbox.children].map(o => o.textContent.trim()).join('\n') : 'no listbox';
"

# Select with arrow keys + Enter
cmux browser $SURFACE press ArrowDown
cmux browser $SURFACE press Enter
```

## Screenshots

Use screenshots when DOM queries aren't enough:

```bash
cmux browser $SURFACE screenshot --out tmp/chat-state.png
```
