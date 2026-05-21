// Reads all messages from a chat by name, returning their HTML content.
// Args: chatName
(function(chatName) {
  // Normalize: strip .chat extension if provided
  const name = chatName.replace(/\.chat$/, '');
  const selector = `#jupyter-chat\\:\\:widget\\:\\:${CSS.escape(name + '.chat')}`;
  const widget = document.querySelector(selector);
  if (!widget) {
    return 'ERROR: chat "' + chatName + '" not found in DOM';
  }

  const messages = widget.querySelectorAll('.jp-chat-message');
  const result = [];

  for (const msg of messages) {
    // Get rendered message content (text, math, etc.)
    const rendered = msg.querySelector('.jp-chat-rendered-message');
    const renderedHtml = rendered ? rendered.innerHTML.trim() : '';

    // Get tool call blocks if present
    const toolCalls = msg.querySelector('.jp-jupyter-ai-acp-client-tool-calls');
    const toolCallsHtml = toolCalls ? toolCalls.outerHTML : '';

    // Get sender and time from header (ignore avatar)
    const header = msg.querySelector('.jp-chat-message-header');
    const headerBox = header?.querySelector('.MuiBox-root');
    const sender = headerBox?.children[0]?.textContent?.trim() || '';
    const time = headerBox?.children[1]?.textContent?.trim() || '';

    result.push({
      sender,
      time,
      content: renderedHtml,
      toolCalls: toolCallsHtml
    });
  }

  return JSON.stringify(result);
})
