// Sends a message to a chat by name, typing character by character.
// Args: chatName, message
(async function(chatName, message) {
  if (!chatName) return 'ERROR: chatName argument is required';
  if (!message) return 'ERROR: message argument is required';

  const app = window.jupyterapp;

  // Open the chat (creates if needed, no-op if already open)
  await app.commands.execute('jupyterlab-chat:createAndOpen', {
    name: chatName,
    inSidePanel: true
  });

  // Get the MultiChatPanel from the left sidebar
  const panel = [...app.shell.widgets('left')]
    .find(w => w.id === 'jupyter-chat::multi-chat-panel');
  if (!panel || !panel.current) {
    return 'ERROR: could not find chat panel';
  }

  const input = panel.current.model.input;
  await panel.current.model.ready;

  // Type character by character (~60 WPM ≈ 20ms per char)
  input.value = '';
  input.cursorIndex = 0;
  for (const char of message) {
    input.value += char;
    input.cursorIndex = input.value.length;
    await new Promise(r => setTimeout(r, 20));
  }

  // Send (same path as pressing Enter in the UI)
  input.send(input.value);
  return 'ok';
})
