// Lists all chat files visible in the Jupyter Chat side panel.
(async function() {
  const app = window.jupyterapp;
  const contents = app.serviceManager.contents;

  // Get the default chat directory (same logic as the side panel)
  const settings = await app.serviceManager.settings.fetch(
    'jupyterlab-chat-extension:factory'
  ).catch(() => null);
  const defaultDir = settings?.composite?.defaultDirectory || '';

  const dirContents = await contents.get(defaultDir);
  const chats = dirContents.content
    .filter(f => f.type === 'file' && f.name.endsWith('.chat'))
    .map(f => f.name.replace('.chat', ''));

  return JSON.stringify(chats);
})
