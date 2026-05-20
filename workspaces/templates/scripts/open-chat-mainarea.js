// Opens a new chat in the JupyterLab main area.
// Expects CHAT_NAME to be replaced before eval.
(async () => {
  const app = window.jupyterapp;
  const chatName = '__CHAT_NAME__';

  // Create a new chat file and open it in the main area
  if (app.commands.hasCommand('jupyter-chat:create')) {
    await app.commands.execute('jupyter-chat:create', { name: chatName, inMainArea: true });
  } else {
    return 'ERROR: jupyter-chat:create command not found. Is the extension installed?';
  }

  return 'ok';
})()
