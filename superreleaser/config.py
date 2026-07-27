"""Static configuration for Superreleaser.

Everything here is data, not secrets. `gh` auth comes from the user's shell;
Prefect's SQLite DB lives outside the repo (default ~/.prefect). Nothing in this
module reaches out to the network — it just resolves names and paths.
"""

from __future__ import annotations

import os
from pathlib import Path

# Where the local Prefect server listens. `just start-superreleaser` brings up
# `prefect server start` here; the serve() executor and every trigger/observer
# talk to this same API. Overridable so the recipe and the flows agree.
PREFECT_API_URL = os.environ.get("PREFECT_API_URL", "http://127.0.0.1:4200/api")
PREFECT_UI_URL = PREFECT_API_URL.replace("/api", "")

# conda-forge feedstocks live as git submodules under this superproject. Each
# subpackage has a `<pkg>-feedstock/recipe/recipe.yaml`. Overridable for CI.
FEEDSTOCKS_ROOT = Path(
    os.environ.get(
        "SUPERRELEASER_FEEDSTOCKS_ROOT",
        str(Path.home() / "workplace" / "jupyter-ai-feedstocks"),
    )
)

# GitHub org that hosts the jupyter-ai subpackage source repos.
GH_ORG = "jupyter-ai-contrib"

# The single knob for "am I allowed to touch the real world?". Defaults to a
# dry run so the whole DAG — including the destructive atoms (prep-release
# push, PyPI/NPM publish, feedstock PR open + merge) — can be exercised
# end-to-end with nothing shipped. The recipe and flow params can flip it.
DRY_RUN_DEFAULT = os.environ.get("SUPERRELEASER_DRY_RUN", "1") != "0"


def gh_repo(package: str) -> str:
    """`jupyter-ai-acp-client` -> `jupyter-ai-contrib/jupyter-ai-acp-client`."""
    return f"{GH_ORG}/{package}"


def pypi_name(package: str) -> str:
    """PyPI project name. The jupyter-ai subpackages publish under their
    hyphenated repo name (PyPI normalizes `_`/`-`), so identity is correct."""
    return package


def feedstock_dir(package: str) -> Path:
    """Path to the `<pkg>-feedstock` submodule checkout."""
    return FEEDSTOCKS_ROOT / f"{package}-feedstock"


def conda_name(dep: str) -> str:
    """Map a PyPI distribution name to its conda-forge package name.

    For the jupyter-ai stack this is identity modulo `_`<->`-` normalization
    (conda-forge uses the same names). Anything genuinely new/renamed is NOT
    guessed here — the feedstock flow flags unknowns at a human gate instead.
    """
    return dep.strip().lower().replace("_", "-")
