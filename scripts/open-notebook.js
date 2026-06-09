// Opens a notebook. If path is given, opens it. Otherwise creates a new untitled notebook.
(async function(path) {
  const app = window.jupyterapp;
  if (path) {
    if (!path.endsWith(".ipynb")) {
      return "ERROR: File not found: \"" + path + "\". Did you forget the .ipynb extension?";
    }
    try {
      await app.serviceManager.contents.get(path, { content: false });
    } catch (e) {
      return "ERROR: File not found: \"" + path + "\". Check the path and ensure the .ipynb extension is included.";
    }
    await app.commands.execute("docmanager:open", {
      path: path,
      factory: "Notebook",
      kernel: { name: "python3" }
    });
    return path;
  } else {
    const widget = await app.commands.execute("notebook:create-new", {
      kernelName: "python3"
    });
    return widget?.context?.path || "new notebook";
  }
})
