---
name: use-page-config
description: Forward immutable data from a Jupyter server extension to a JupyterLab frontend extension at startup via PageConfig, avoiding a network request on init. Use when a lab extension needs server-side data known at server start (traitlets config, entry-point data, feature flags), or when told to read this skill to understand PageConfig.
---

# Use PageConfig to pass server data to the frontend

`page_config_data` is a dict the Jupyter **server** fills at startup and the
**frontend** reads synchronously via `PageConfig.getOption(...)`. It's baked into
the page's HTML when JupyterLab loads, so the frontend has the value immediately —
**no REST/WebSocket round-trip on init.**

## When to use this

Use it for **immutable data known once, at server start**:

- traitlets configuration values (feature flags, modes, limits)
- data derived from entry points / installed extensions
- anything the frontend needs at activation that never changes for the life of the
  server process

**Do NOT use it for mutable or per-request data.** `page_config_data` is a snapshot
taken when the server starts; it does not update afterward. For data that changes
during a session, use a REST endpoint, the Yjs document (metadata/awareness), or a
WebSocket.

## Server side — set the value

In your `ExtensionApp.initialize_settings()`, write into the `page_config_data`
dict on the web app settings. Reference: the merged pattern in
[`jupyter-server-documents` PR #247](https://github.com/jupyter-ai-contrib/jupyter-server-documents/pull/247)
(`jupyter_server_documents/app.py`, `initialize_settings`).

```python
from jupyter_server.extension.application import ExtensionApp
from traitlets import Bool


class MyApp(ExtensionApp):
    name = "myapp"
    my_flag = Bool(False, help="my custom setting").tag(config=True)

    def initialize_settings(self):
        super().initialize_settings()

        # `page_config_data` may not exist yet — setdefault creates it once,
        # then every extension merges its own keys into the shared dict.
        page_config = self.serverapp.web_app.settings.setdefault("page_config_data", {})

        # Values are serialized into the page as strings. Write strings, not
        # Python bools/ints — "true"/"false", not True/False.
        page_config["myapp_my_flag"] = str(self.my_flag).lower()
```

Key points:
- **`setdefault("page_config_data", {})`** — the dict is shared across all server
  extensions. Never overwrite it; merge your keys in.
- **Values must be strings.** `page_config_data` is rendered into HTML, so booleans
  become `"true"`/`"false"` via `str(value).lower()`. Numbers → `str(n)`. Structured
  data → `json.dumps(...)` on the server, `JSON.parse(...)` on the frontend.
- **Name your keys to avoid collisions.** The dict is global to the server, so
  prefix keys with your extension name (e.g. `myapp_my_flag`) unless the key is
  already clearly unique.

## Frontend side — read the value

```ts
import { PageConfig } from '@jupyterlab/coreutils';

// Everything comes back as a string (or '' if the key is absent).
const myFlag = PageConfig.getOption('myapp_my_flag') === 'true';
```

A common pattern is to gate an entire plugin on a server flag, so frontend code
only runs when the server enabled the feature (as PR #247 does for its outputs
service):

```ts
import { PageConfig } from '@jupyterlab/coreutils';

const plugin: JupyterFrontEndPlugin<void> = {
  id: 'myapp:optional-feature',
  autoStart: true,
  activate: (app: JupyterFrontEnd) => {
    const enabled = PageConfig.getOption('myapp_my_flag') === 'true';
    if (!enabled) {
      return; // server didn't enable it — do nothing
    }
    // ... set up the feature ...
  }
};
```

Built-in options are also available through the same API, e.g.:

```ts
const baseUrl = PageConfig.getOption('baseUrl');
const token = PageConfig.getToken();
```

## Gotchas

- **Strings only.** Reading a key you set as a Python `True` gives `"True"`, not
  `"true"` — always `str(...).lower()` on the server and compare to `'true'`.
- **Absent key → `''`.** `getOption` returns an empty string for unknown keys, not
  `undefined`. Check explicitly.
- **Computed once, then cached.** JupyterLab builds the page config in
  `LabHandler.get_page_config()` (`jupyterlab_server/handlers.py`), which is
  decorated with `@lru_cache` — it reads `page_config_data` on the **first** page
  request and never again for the life of the process. So whatever you want the
  frontend to see must already be in the dict by then.
- **Set it in `initialize_settings()`.** That runs during server startup, before
  any page is served, so your keys are present when `get_page_config()` first
  runs. Writing to `page_config_data` later (e.g. per-request) won't reach the
  page — the cached config already excludes it. This is why the mechanism only
  fits data known at startup: not because traitlets can't change (they generally
  don't at runtime anyway), but because the page config is read exactly once.
