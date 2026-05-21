// Opens a new chat in the JupyterLab main area.
(async function(chatName) {
  const app = window.jupyterapp;

  if (!app.commands.hasCommand('jupyterlab-chat:createAndOpen')) {
    return 'ERROR: jupyterlab-chat commands not registered. Is the extension installed?';
  }

  await app.commands.execute('jupyterlab-chat:createAndOpen', {
    name: chatName,
    inSidePanel: false
  });

  return chatName;
})
