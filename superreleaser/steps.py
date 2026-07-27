"""The deterministic building-block steps, as Prefect tasks.

Each task is one real release atom (trigger a workflow, poll PyPI, open a
feedstock PR). The two that touch the outside world irreversibly — publishing
and merging — honor `dry_run`: in dry-run they log the exact command they WOULD
run and return a synthetic-but-plausible result, so the whole DAG can be walked
without shipping anything. The gates (suspend_flow_run) are always real: they
live in Prefect's DB and survive the Claude terminal closing.
"""

from __future__ import annotations

import json
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path

from packaging.version import InvalidVersion, Version
from prefect import get_run_logger, task

from . import config


# --------------------------------------------------------------------------- #
# Shell / gh helpers
# --------------------------------------------------------------------------- #
def _run(cmd: list[str], *, cwd: Path | None = None, check: bool = True) -> str:
    """Run a command, returning stdout. Logs the command line first."""
    logger = get_run_logger()
    logger.info("$ %s%s", " ".join(cmd), f"  (cwd={cwd})" if cwd else "")
    proc = subprocess.run(
        cmd, cwd=cwd, capture_output=True, text=True, check=False
    )
    if proc.stdout:
        logger.info(proc.stdout.rstrip())
    if proc.returncode != 0:
        logger.error(proc.stderr.rstrip())
        if check:
            raise RuntimeError(
                f"command failed ({proc.returncode}): {' '.join(cmd)}\n{proc.stderr}"
            )
    return proc.stdout.strip()


def _http_json(url: str) -> dict | None:
    """GET a JSON URL. Returns None on 404 (not-yet-available), raises on other
    errors."""
    try:
        with urllib.request.urlopen(url, timeout=15) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise


def is_prerelease(version_spec: str) -> bool:
    """Best-effort: is this version a prerelease? Used to decide since_last_stable
    and whether to run the conda-forge leg. Non-PEP440 specs like `next`/`patch`
    are treated as stable (the common release path)."""
    try:
        return Version(version_spec.lstrip("v")).is_prerelease
    except InvalidVersion:
        return False


# --------------------------------------------------------------------------- #
# Step 1 — Prep Release (draft)
# --------------------------------------------------------------------------- #
@task(retries=0)
def prep_release(
    package: str, version_spec: str, branch: str, *, dry_run: bool
) -> str:
    """Trigger "Step 1: Prep Release" and watch it green.

    since_last_stable is True for stable releases, False for prereleases (a
    prerelease's changelog should span back to the last *stable*'s successor,
    which releaser handles when the flag is off and `since` is empty).
    """
    logger = get_run_logger()
    repo = config.gh_repo(package)
    stable = not is_prerelease(version_spec)
    fields = [
        f"version_spec={version_spec}",
        f"branch={branch}",
        f"since_last_stable={'true' if stable else 'false'}",
    ]
    cmd = ["gh", "workflow", "run", "Step 1: Prep Release", "--repo", repo, "--ref", branch]
    for f in fields:
        cmd += ["-f", f]

    if dry_run:
        logger.info("[dry-run] would trigger prep-release:\n  %s", " ".join(cmd))
        logger.info("[dry-run] would then: gh run watch <run-id> --repo %s", repo)
        return "DRY-RUN"

    _run(cmd)
    # Real path: find the just-created run and watch it.
    run_id = _run(
        ["gh", "run", "list", "--repo", repo, "--workflow", "prep-release.yml",
         "--limit", "1", "--json", "databaseId", "--jq", ".[0].databaseId"]
    )
    _run(["gh", "run", "watch", run_id, "--repo", repo, "--exit-status"])
    return run_id


@task(retries=10, retry_delay_seconds=15)
def await_draft_release(package: str, *, dry_run: bool) -> str:
    """Await the draft GitHub release to exist; return its URL. Retries act as
    the poll loop."""
    logger = get_run_logger()
    repo = config.gh_repo(package)
    if dry_run:
        url = f"https://github.com/{repo}/releases/tag/untagged-DRYRUN"
        logger.info("[dry-run] would poll for draft release; pretending: %s", url)
        return url

    out = _run(
        ["gh", "release", "list", "--repo", repo, "--json",
         "isDraft,tagName,url", "--jq",
         "[.[] | select(.isDraft)] | .[0].url // empty"],
        check=False,
    )
    if not out:
        raise RuntimeError("draft release not present yet")  # triggers retry
    return out


# --------------------------------------------------------------------------- #
# Step 2 — Publish Release  (DESTRUCTIVE: dry-run by default)
# --------------------------------------------------------------------------- #
@task(retries=0)
def publish_release(
    package: str, branch: str, release_url: str, *, dry_run: bool
) -> None:
    logger = get_run_logger()
    repo = config.gh_repo(package)
    cmd = ["gh", "workflow", "run", "Step 2: Publish Release", "--repo", repo,
           "--ref", branch, "-f", f"branch={branch}", "-f", f"release_url={release_url}"]
    if dry_run:
        logger.info("[dry-run] WOULD PUBLISH (skipped):\n  %s", " ".join(cmd))
        return
    _run(cmd)
    run_id = _run(
        ["gh", "run", "list", "--repo", repo, "--workflow", "publish-release.yml",
         "--limit", "1", "--json", "databaseId", "--jq", ".[0].databaseId"]
    )
    _run(["gh", "run", "watch", run_id, "--repo", repo, "--exit-status"])


@task(retries=60, retry_delay_seconds=30)
def await_pypi(package: str, version: str, *, dry_run: bool) -> str:
    """Poll PyPI until the sdist for <version> is up; return its sha256 (the
    signal the feedstock hash can be computed). Retries = poll loop."""
    logger = get_run_logger()
    name = config.pypi_name(package)
    version = version.lstrip("v")
    url = f"https://pypi.org/pypi/{name}/{version}/json"
    if dry_run:
        logger.info("[dry-run] would poll %s until sdist appears", url)
        return "0" * 64
    data = _http_json(url)
    if not data:
        raise RuntimeError(f"{name} {version} not on PyPI yet")  # retry
    sdist = next(
        (u for u in data["urls"] if u["url"].endswith(".tar.gz")), None
    )
    if not sdist:
        raise RuntimeError("sdist not present in PyPI files yet")  # retry
    logger.info("PyPI sdist available: %s", sdist["url"])
    return sdist["digests"]["sha256"]
