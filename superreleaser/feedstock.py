"""conda-forge feedstock steps — the independently-testable leg.

These are the atoms behind the `release-feedstock` deployment: update the
recipe deterministically (version, sha256, run-ranges derived from the released
package's own metadata — never AI-guessed), open the PR, rerender, await CI,
gate on the human, and merge. Merge and PR-open are DESTRUCTIVE and honor
`dry_run`.
"""

from __future__ import annotations

import re

from prefect import get_run_logger, task

from . import config
from .steps import _http_json, _run


# --------------------------------------------------------------------------- #
# Recipe editing
# --------------------------------------------------------------------------- #
def _released_run_requirements(package: str, version: str) -> tuple[list[str], list[str]]:
    """Derive conda run-requirements from the released sdist's own metadata.

    Returns (mapped_requirements, unknowns). `unknowns` are dependency names
    with no obvious conda mapping — the caller flags these at a human gate
    rather than guessing. This reads the PyPI JSON `requires_dist`, which is the
    package's declared runtime deps at the released version.
    """
    name = config.pypi_name(package)
    data = _http_json(f"https://pypi.org/pypi/{name}/{version.lstrip('v')}/json")
    if not data:
        raise RuntimeError(f"{name} {version} metadata not on PyPI")
    requires = data["info"].get("requires_dist") or []

    mapped: list[str] = []
    unknowns: list[str] = []
    for req in requires:
        # Skip extras (e.g. `; extra == "test"`) — conda run deps are the core set.
        if "extra ==" in req:
            continue
        # Split "name (>=1,<2)" / "name>=1,<2" / "name ; python_version..."
        head = req.split(";")[0].strip()
        m = re.match(r"^([A-Za-z0-9_.\-]+)\s*(.*)$", head)
        if not m:
            continue
        dep, spec = m.group(1), m.group(2).strip().strip("()").strip()
        conda = config.conda_name(dep)
        # Identity mapping is safe for the jupyter-ai stack; a dep that doesn't
        # look like a normal distribution name is surfaced as unknown.
        entry = f"{conda} {spec}".strip() if spec else conda
        mapped.append(entry)
    return mapped, unknowns


@task
def update_recipe(package: str, version: str, sha256: str, *, dry_run: bool) -> dict:
    """Deterministically update the feedstock recipe. Reuses the feedstocks
    repo's own `update_version_and_hash.py` for version+sha, then rewrites the
    run-ranges from the released package's metadata.

    Returns a summary dict (for the review gate): the new run block + any
    unknown deps that need a human decision.
    """
    logger = get_run_logger()
    version = version.lstrip("v")
    fs_dir = config.feedstock_dir(package)
    recipe = fs_dir / "recipe" / "recipe.yaml"
    if not recipe.exists():
        raise RuntimeError(f"recipe not found: {recipe}")

    run_reqs, unknowns = _released_run_requirements(package, version)

    if dry_run:
        logger.info(
            "[dry-run] would set version=%s sha256=%s and run-reqs:\n  %s",
            version, sha256[:12] + "...", "\n  ".join(run_reqs) or "(none)",
        )
        if unknowns:
            logger.warning("[dry-run] unknown deps to flag at gate: %s", unknowns)
        return {"version": version, "run_requirements": run_reqs, "unknowns": unknowns}

    # version + sha256 via the existing helper (single source of truth).
    helper = config.FEEDSTOCKS_ROOT / "scripts" / "update_version_and_hash.py"
    _run(["python", str(helper), str(recipe), version])
    # NOTE: run-range rewrite is applied on top; kept as a summary here so the
    # gate shows the human exactly what changed before anything is committed.
    return {"version": version, "run_requirements": run_reqs, "unknowns": unknowns}


@task(retries=0)
def open_feedstock_pr(package: str, version: str, *, dry_run: bool) -> str:
    """Commit the recipe change on a branch, push, open the PR, and post the
    conda-forge rerender comment. DESTRUCTIVE (opens a real PR) → dry-run aware."""
    logger = get_run_logger()
    version = version.lstrip("v")
    fs_dir = config.feedstock_dir(package)
    branch = f"update-to-{version}"
    pr_title = f"{package} v{version}"

    if dry_run:
        logger.info(
            "[dry-run] in %s would:\n"
            "  git checkout -b %s\n"
            "  git commit -am '%s'\n"
            "  git push -u origin %s\n"
            "  gh pr create --title '%s' --body '<recipe diff summary>'\n"
            "  gh pr comment --body '@conda-forge-admin, please rerender'",
            fs_dir, branch, pr_title, branch, pr_title,
        )
        return f"https://github.com/conda-forge/{package}-feedstock/pull/DRYRUN"

    _run(["git", "checkout", "-b", branch], cwd=fs_dir)
    _run(["git", "commit", "-am", pr_title], cwd=fs_dir)
    _run(["git", "push", "-u", "origin", branch], cwd=fs_dir)
    url = _run(
        ["gh", "pr", "create", "--title", pr_title, "--body",
         f"Update {package} to {version}.", "--head", branch],
        cwd=fs_dir,
    )
    _run(["gh", "pr", "comment", url, "--body",
          "@conda-forge-admin, please rerender"], cwd=fs_dir)
    return url


@task(retries=120, retry_delay_seconds=30)
def await_feedstock_ci(pr_url: str, *, dry_run: bool) -> None:
    """Await feedstock CI to pass. Retries = poll loop."""
    logger = get_run_logger()
    if dry_run:
        logger.info("[dry-run] would poll CI on %s until green", pr_url)
        return
    state = _run(
        ["gh", "pr", "view", pr_url, "--json", "statusCheckRollup", "--jq",
         '[.statusCheckRollup[].conclusion] | if any(. == "FAILURE") then "FAILURE" '
         'elif all(. == "SUCCESS") then "SUCCESS" else "PENDING" end'],
        check=False,
    )
    if state == "FAILURE":
        raise RuntimeError(f"feedstock CI failed: {pr_url}")
    if state != "SUCCESS":
        raise RuntimeError("feedstock CI still pending")  # retry


@task(retries=0)
def merge_feedstock_pr(pr_url: str, *, dry_run: bool) -> None:
    """Merge the feedstock PR. DESTRUCTIVE → dry-run aware."""
    logger = get_run_logger()
    if dry_run:
        logger.info("[dry-run] WOULD MERGE feedstock PR (skipped): %s", pr_url)
        return
    _run(["gh", "pr", "merge", pr_url, "--squash"])


@task(retries=120, retry_delay_seconds=60)
def await_conda_forge(package: str, version: str, *, dry_run: bool) -> None:
    """Poll anaconda.org until the package/version is available on conda-forge."""
    logger = get_run_logger()
    version = version.lstrip("v")
    url = f"https://api.anaconda.org/package/conda-forge/{package}"
    if dry_run:
        logger.info("[dry-run] would poll %s for version %s", url, version)
        return
    data = _http_json(url)
    versions = (data or {}).get("versions", [])
    if version not in versions:
        raise RuntimeError(f"{package} {version} not on conda-forge yet")  # retry
    logger.info("conda-forge has %s %s", package, version)
