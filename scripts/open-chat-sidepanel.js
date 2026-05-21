// Opens a new chat in the Jupyter Chat side panel.
(async function(chatName) {
  if (!chatName) return 'ERROR: chatName argument is required';

  const app = window.jupyterapp;

  if (!app.commands.hasCommand('jupyter-chat:open')) {
    return 'ERROR: jupyter-chat commands not registered. Is the extension installed?';
  }

  await app.commands.execute('jupyter-chat:open');

  if (!app.commands.hasCommand('jupyter-chat:create')) {
    return 'ERROR: jupyter-chat:create command not found.';
  }

  await app.commands.execute('jupyter-chat:create', { name: chatName });
  return chatName;
})
