#!/usr/bin/env python3
"""Patch pyproject.toml to add workspace packages."""
import re
import sys
from pathlib import Path

MARKER = "    # --- workspace packages (editable) ---"

def get_pkg_name(repo: str) -> str:
    if repo == "jupyter-chat":
        toml_path = Path("jupyter-chat/python/jupyterlab-chat/pyproject.toml")
    else:
        toml_path = Path(repo) / "pyproject.toml"
    for line in toml_path.read_text().splitlines():
        if line.startswith("name"):
            return line.split('"')[1]
    raise ValueError(f"Could not find package name in {toml_path}")

def get_member_path(repo: str) -> str:
    if repo == "jupyter-chat":
        return "jupyter-chat/python/jupyterlab-chat"
    return repo

def patch(repos: list[str]):
    toml = Path("pyproject.toml")
    content = toml.read_text()

    for repo in repos:
        pkg_name = get_pkg_name(repo)
        member_path = get_member_path(repo)

        # Add marker if missing
        if MARKER not in content:
            content = content.replace(
                '    "jupyterlab>=4",\n]',
                '    "jupyterlab>=4",\n' + MARKER + '\n]'
            )

        # Add package to dependencies
        if f'"{pkg_name}"' not in content:
            content = content.replace(
                MARKER,
                MARKER + f'\n    "{pkg_name}",'
            )

        # Add [tool.uv.sources] if missing
        if "[tool.uv.sources]" not in content:
            content += "\n[tool.uv.sources]\n"

        # Add workspace source
        source_line = f'{pkg_name} = {{ workspace = true }}'
        if source_line not in content:
            content = content.replace(
                "[tool.uv.sources]",
                f"[tool.uv.sources]\n{source_line}"
            )

        # Update members list
        m = re.search(r'members = \[(.*?)\]', content, re.DOTALL)
        if m:
            existing = [x.strip().strip('"').strip("'") for x in m.group(1).split(',') if x.strip()]
            if member_path not in existing:
                existing.append(member_path)
            members_str = ", ".join(f'"{x}"' for x in sorted(existing))
            content = re.sub(r'members = \[.*?\]', f'members = [{members_str}]', content, flags=re.DOTALL)

    toml.write_text(content)

if __name__ == "__main__":
    patch(sys.argv[1:])
