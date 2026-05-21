// Opens a new chat in the JupyterLab main area.
(async function(chatName) {
  if (!chatName) return 'ERROR: chatName argument is required';

  const app = window.jupyterapp;

  if (!app.commands.hasCommand('jupyter-chat:create')) {
    return 'ERROR: jupyter-chat:create command not found. Is the extension installed?';
  }

  await app.commands.execute('jupyter-chat:create', { name: chatName, inMainArea: true });
  return chatName;
})
