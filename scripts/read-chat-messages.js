// Reads all messages from a chat by name, returning their HTML content.
// Args: chatName
(function(chatName) {
  const name = chatName.replace(/\.chat$/, '');

  // Find the chat widget container:
  // 1. Side panel: widget ID contains the chat name
  // 2. Main area: find tab by title, then panel by data-id
  let container = document.querySelector('#jupyter-chat\\:\\:widget\\:\\:' + CSS.escape(name + '.chat'));
  if (!container) {
    const tab = document.querySelector('li.lm-TabBar-tab[title*="' + name + '.chat"]');
    if (tab && tab.dataset.id) {
      container = document.getElementById(tab.dataset.id);
    }
  }
  if (!container) {
    return 'ERROR: chat "' + chatName + '" not found in DOM';
  }

  const messages = container.querySelectorAll('.jp-chat-message');
  const result = [];

  for (const msg of messages) {
    // Get rendered message content as array of typed blocks
    const rendered = msg.querySelector('.jp-chat-rendered-message .jp-RenderedMarkdown');
    const content = [];
    if (rendered) {
      for (const child of rendered.children) {
        if (child.tagName === 'PRE') {
          const next = child.nextElementSibling;
          const toolbar = next?.querySelector('.jp-chat-code-toolbar');
          const msgContainer = child.closest('.jp-chat-message-container');
          const idx = msgContainer?.dataset?.index;
          const toolbarButtons = toolbar
            ? [...toolbar.querySelectorAll('button')].map(b => {
                const label = b.getAttribute('aria-label');
                const sel = idx != null
                  ? `[data-index="${idx}"] button[aria-label*="${label.split('(')[0].trim()}"]`
                  : `button[aria-label*="${label.split('(')[0].trim()}"]`;
                return sel;
              })
            : [];
          content.push({ type: 'code', value: child.textContent, toolbarButtons });
        } else if (child.classList.contains('jp-chat-code-toolbar')) {
          continue; // skip toolbar
        } else if (child.querySelector('mjx-container[display="true"]')) {
          content.push({ type: 'math-block', value: child.textContent.trim() });
        } else if (child.querySelector('mjx-container')) {
          content.push({ type: 'math-inline', value: child.textContent.trim() });
        } else if (child.textContent.trim()) {
          content.push({ type: 'text', value: child.textContent.trim() });
        }
      }
    }

    // Get tool call blocks if present
    const toolCallsEl = msg.querySelector('.jp-jupyter-ai-acp-client-tool-calls');
    const toolCalls = [];
    if (toolCallsEl) {
      for (const call of toolCallsEl.querySelectorAll('.jp-jupyter-ai-acp-client-tool-call')) {
        toolCalls.push({
          status: call.className.match(/tool-call-(\w+)/)?.[1] || 'unknown',
          summary: call.querySelector('summary')?.textContent?.trim() || '',
          files: [...call.querySelectorAll('.jp-jupyter-ai-acp-client-diff-header')].map(h => h.textContent),
          lines: [...call.querySelectorAll('.jp-jupyter-ai-acp-client-diff-line-text')].map(l => l.textContent),
          permissionButtons: [...call.querySelectorAll('.jp-jupyter-ai-acp-client-permission-btn')].map(b => {
            const btnClass = [...b.classList].find(c => c.startsWith('jp-jupyter-ai-acp-client-permission-btn-'));
            return {
              label: b.textContent,
              selector: `#${CSS.escape(container.id)} .${btnClass}:not([disabled])`
            };
          })
        });
      }
    }

    // Get sender and time from header (ignore avatar)
    const header = msg.querySelector('.jp-chat-message-header');
    const headerBox = header?.querySelector('.MuiBox-root');
    const sender = headerBox?.children[0]?.textContent?.trim() || 'self';
    const time = headerBox?.children[1]?.textContent?.trim() || '';

    result.push({
      sender,
      time,
      content,
      toolCalls
    });
  }

  return JSON.stringify(result);
})
