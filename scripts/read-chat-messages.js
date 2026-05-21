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

    // Get message header (author, time)
    const header = msg.querySelector('.jp-chat-message-header');
    const time = header?.querySelector('.jp-chat-message-time')?.getAttribute('title') || '';
    const avatar = header?.querySelector('.MuiAvatar-root');
    const sender = avatar?.getAttribute('title') || '';

    result.push({
      sender,
      time,
      content: renderedHtml,
      toolCalls: toolCallsHtml
    });
  }

  return JSON.stringify(result);
})
