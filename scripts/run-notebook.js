// Opens a notebook and runs all cells. Path is required.
(async function(path) {
  const app = window.jupyterapp;
  if (!path.endsWith(".ipynb")) {
    return "ERROR: File not found: \"" + path + "\". Did you forget the .ipynb extension?";
  }
  try {
    await app.serviceManager.contents.get(path, { content: false });
  } catch (e) {
    return "ERROR: File not found: \"" + path + "\". Check the path and ensure the .ipynb extension is included.";
  }
  const widget = await app.commands.execute("docmanager:open", {
    path: path,
    factory: "Notebook",
    kernel: { name: "python3" }
  });
  if (widget && widget.sessionContext) {
    await widget.sessionContext.ready;
  }
  await app.commands.execute("notebook:run-all-cells");
  return path;
})
