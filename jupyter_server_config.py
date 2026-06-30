# jupyter_server_config.py
from pathlib import Path

# Root the server in tmp/ so runtime files (.jupyter/, untitled.chat) and the
# YStore db stay out of the workspace root and don't show up as dirty git state.
_tmp = Path(__file__).parent / "tmp"
_tmp.mkdir(exist_ok=True)
c.ServerApp.root_dir = str(_tmp)
c.SQLiteYStore.db_path = str(_tmp / ".jupyter_ystore.db")

c.MCPExtensionApp.mcp_port = 18741
c.MCPExtensionApp.mcp_name = "Jupyter MCP Server"
c.YRoomManager.auto_free_interval = 1
c.YRoomManager.show_gc_debug = True
c.YRoom.inactivity_timeout = 1
