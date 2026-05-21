// Opens a new chat in the Jupyter Chat side panel.
(async function(chatName) {
  const app = window.jupyterapp;

  if (!app.commands.hasCommand('jupyterlab-chat:createAndOpen')) {
    return 'ERROR: jupyterlab-chat commands not registered. Is the extension installed?';
  }

  await app.commands.execute('jupyterlab-chat:createAndOpen', {
    name: chatName,
    inSidePanel: true
  });

  return chatName;
})
