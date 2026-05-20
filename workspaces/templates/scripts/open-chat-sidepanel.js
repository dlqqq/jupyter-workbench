// Opens a new chat in the Jupyter Chat side panel.
// Expects CHAT_NAME to be replaced before eval.
(async () => {
  const app = window.jupyterapp;
  const chatName = '__CHAT_NAME__';

  // Open the side panel if not already visible
  if (app.commands.hasCommand('jupyter-chat:open')) {
    await app.commands.execute('jupyter-chat:open');
  } else {
    return 'ERROR: jupyter-chat commands not registered. Is the extension installed?';
  }

  // Create a new chat file via the chat panel's "new chat" command
  if (app.commands.hasCommand('jupyter-chat:create')) {
    await app.commands.execute('jupyter-chat:create', { name: chatName });
  } else {
    return 'ERROR: jupyter-chat:create command not found.';
  }

  return 'ok';
})()
