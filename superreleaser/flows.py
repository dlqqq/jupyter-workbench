"""The three Superreleaser flows (deployments).

Data-driven: these are registered ONCE by serve() and never regenerated. The
agent's job is to emit a `plan` and trigger ONE `release-batch` run.

  release-subpackage  — the building block: prep → gate → publish → PyPI →
                        (stable only) hand off to release-feedstock.
  release-feedstock   — the conda-forge leg, independently triggerable.
  release-batch       — orchestrator: runs `plan` waves in order, each wave's
                        subpackages concurrent, waves sequential, metapackage last.

Human gates use suspend_flow_run: the run's paused state lives in Prefect's DB
and survives the Claude terminal closing. The gate's Markdown description (via a
RunInput subclass) carries the clickable review URL so approval happens in the
Prefect UI, not by talking to the agent.
"""

from __future__ import annotations

from typing import Any

from prefect import flow, get_run_logger, task
from prefect.deployments import run_deployment
from prefect.flow_runs import suspend_flow_run
from prefect.input import RunInput

from . import config, feedstock, steps


@task
def _release_one(entry: dict, dry_run: bool) -> dict:
    """Trigger one child release-subpackage run and block until it finishes.
    Submitted concurrently within a wave; the wave barrier awaits all of them."""
    run = run_deployment(
        name="release-subpackage/release-subpackage",
        parameters={
            "package": entry["package"],
            "version_spec": entry["version_spec"],
            "branch": entry.get("branch", "main"),
            "dry_run": dry_run,
            "include_feedstock": entry.get("include_feedstock", True),
        },
    )
    return {"package": entry["package"], "run": run.name, "state": str(run.state_type)}


class GateDecision(RunInput):
    """The human's answer at a gate. `approve=False` stops the release."""

    approve: bool
    note: str = ""


def _gate(title: str, markdown: str) -> GateDecision:
    """Suspend the flow for human review. The description renders as Markdown in
    the Prefect UI (Resume dialog), so review links are clickable there."""
    logger = get_run_logger()
    logger.info("GATE: %s — suspending for human review in the Prefect UI", title)
    model = GateDecision.with_initial_data(description=markdown)
    return suspend_flow_run(wait_for_input=model)


# --------------------------------------------------------------------------- #
# release-feedstock — the conda-forge leg (independently testable)
# --------------------------------------------------------------------------- #
@flow(name="release-feedstock")
def release_feedstock(
    package: str,
    version: str,
    sha256: str = "",
    dry_run: bool = config.DRY_RUN_DEFAULT,
) -> dict:
    """Steps 6–9: update recipe → open PR + rerender → await CI → GATE → merge →
    await conda-forge. `sha256` may be passed in from the PyPI step; if empty
    (running this leg standalone), await_pypi resolves it."""
    logger = get_run_logger()
    logger.info("release-feedstock: %s %s (dry_run=%s)", package, version, dry_run)

    if not sha256:
        sha256 = steps.await_pypi(package, version, dry_run=dry_run)

    summary = feedstock.update_recipe(package, version, sha256, dry_run=dry_run)
    pr_url = feedstock.open_feedstock_pr(package, version, dry_run=dry_run)
    feedstock.await_feedstock_ci(pr_url, dry_run=dry_run)

    unknowns = summary.get("unknowns") or []
    md = (
        f"### Review feedstock PR for `{package}` {version}\n\n"
        f"**PR:** {pr_url}\n\n"
        f"**Run requirements:**\n\n"
        + "\n".join(f"- `{r}`" for r in summary["run_requirements"])
        + (
            f"\n\n**⚠️ Unknown deps (no obvious conda mapping — decide manually):**\n\n"
            + "\n".join(f"- `{u}`" for u in unknowns)
            if unknowns
            else ""
        )
        + "\n\nApprove to merge, reject to stop."
    )
    decision = _gate("feedstock PR review", md)
    if not decision.approve:
        logger.warning("feedstock rejected: %s", decision.note)
        return {"status": "rejected-feedstock", "pr_url": pr_url}

    feedstock.merge_feedstock_pr(pr_url, dry_run=dry_run)
    feedstock.await_conda_forge(package, version, dry_run=dry_run)
    return {"status": "released-feedstock", "pr_url": pr_url}


# --------------------------------------------------------------------------- #
# release-subpackage — the building block
# --------------------------------------------------------------------------- #
@flow(name="release-subpackage")
def release_subpackage(
    package: str,
    version_spec: str,
    branch: str = "main",
    dry_run: bool = config.DRY_RUN_DEFAULT,
    include_feedstock: bool = True,
) -> dict:
    """Steps 1–5 then hand off to release-feedstock (stable only).

    The conda-forge leg is SKIPPED for prereleases (there is no conda-forge
    prerelease channel in this stack) and when include_feedstock is False.
    """
    logger = get_run_logger()
    logger.info(
        "release-subpackage: %s %s on %s (dry_run=%s)",
        package, version_spec, branch, dry_run,
    )

    # Step 1–2: prep the draft release, then await + capture its URL.
    steps.prep_release(package, version_spec, branch, dry_run=dry_run)
    release_url = steps.await_draft_release(package, dry_run=dry_run)

    # Step 3: GATE — review the draft changelog.
    md = (
        f"### Review draft changelog for `{package}` {version_spec}\n\n"
        f"**Draft release:** {release_url}\n\n"
        "Review the generated changelog. Approve to publish, reject to stop "
        "(nothing is published)."
    )
    decision = _gate("draft changelog review", md)
    if not decision.approve:
        logger.warning("release rejected at changelog gate: %s", decision.note)
        return {"status": "rejected-changelog", "release_url": release_url}

    # Step 4–5: publish, then await PyPI + capture the sdist sha256.
    steps.publish_release(package, branch, release_url, dry_run=dry_run)
    sha256 = steps.await_pypi(package, version_spec, dry_run=dry_run)

    prerelease = steps.is_prerelease(version_spec)
    if not include_feedstock or prerelease:
        logger.info(
            "skipping conda-forge leg (%s)",
            "prerelease" if prerelease else "include_feedstock=False",
        )
        return {"status": "released-pypi", "release_url": release_url}

    # Steps 6–9: run the conda-forge leg as a subflow (same server, same DB).
    fs = release_feedstock(package, version_spec, sha256=sha256, dry_run=dry_run)
    return {"status": fs["status"], "release_url": release_url, "feedstock": fs}


# --------------------------------------------------------------------------- #
# release-batch — the generic orchestrator
# --------------------------------------------------------------------------- #
@flow(name="release-batch")
def release_batch(plan: dict[str, Any], dry_run: bool = config.DRY_RUN_DEFAULT) -> dict:
    """Run a release `plan`: ordered waves, each wave's subpackages concurrent,
    waves sequential (metapackage naturally goes in the last wave).

    plan schema:
      {
        "dry_run": true,                 # optional; overrides param
        "waves": [
          [{"package": "...", "version_spec": "...", "branch": "main",
            "include_feedstock": true}, ...],   # wave 0
          [...],                                # wave 1
        ]
      }

    Each entry becomes a child `release-subpackage` run via run_deployment, so
    every subpackage gets its own gates and its own row in the dashboard.
    """
    logger = get_run_logger()
    dry_run = plan.get("dry_run", dry_run)
    waves = plan["waves"]
    logger.info("release-batch: %d wave(s), dry_run=%s", len(waves), dry_run)

    results: list[dict] = []
    for i, wave in enumerate(waves):
        logger.info("── wave %d: %d package(s) ──", i, len(wave))
        # Submit every subpackage in the wave concurrently, then await them all
        # before starting the next wave (waves are sequential, packages within a
        # wave are parallel — metapackage naturally lands in the last wave).
        futures = [_release_one.submit(entry, dry_run) for entry in wave]
        results.append({"wave": i, "runs": [f.result() for f in futures]})
    return {"waves": results}
