// Sends a message to a chat by name, typing character by character.
// Args: chatName, message
(async function(chatName, message) {
  const app = window.jupyterapp;

  // Normalize: strip .chat extension if provided
  const name = chatName.replace(/\.chat$/, '');

  // Search all shell areas for the chat widget
  const areas = ['left', 'right', 'main'];
  let input = null;

  for (const area of areas) {
    for (const widget of app.shell.widgets(area)) {
      // Side panel: check current chat name
      if (widget.current && widget.current.model) {
        const modelName = widget.current.model.name.replace(/\.chat$/, '');
        if (modelName === name) {
          input = widget.current.model.input;
          break;
        }
      }
      // Main area: LabChatPanel by widget ID
      if (widget.id === `jupyter-chat::widget::${name}`) {
        input = widget.model.input;
        break;
      }
    }
    if (input) break;
  }

  if (!input) {
    return 'ERROR: chat "' + chatName + '" not found in any area';
  }

  // Type character by character (~60 WPM)
  input.value = '';
  input.cursorIndex = 0;
  for (let i = 0; i < message.length; i++) {
    input.value = message.slice(0, i + 1);
    input.cursorIndex = i + 1;
    await new Promise(r => setTimeout(r, 80));
  }

  // Send (same path as pressing Enter in the UI)
  input.send(input.value);
  return 'ok';
})
