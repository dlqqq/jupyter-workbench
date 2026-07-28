"""conda-forge release DAG for one Jupyter AI subpackage.

A linear, human-gated pipeline that automates the conda-forge feedstock release
headache. Trigger it with a `dag_run.conf` of `{"package": "jupyter-ai-acp-client"}`
(optionally `{"version": "0.2.1", "dry_run": true}`); it walks:

  1. checkout      — sync the feedstock submodule to its remote default branch
  2. pick_version  — earliest STABLE PyPI version missing from the feedstock
  3. update_recipe — version + PyPI sha256 + run-ranges from the released
                     package's own metadata; NEW deps resolved by PROBING
                     conda-forge (never guessed), unknowns tracked as state
  4. verify_cf     — every mapped dep exists on conda-forge AND its range
                     resolves to a build
  5. open_pr       — real PR; DRAFT + explanatory comment if any dep was
                     unresolved; otherwise a normal PR
  6. wait_for_ci   — sensor polling the PR's checks to pass/fail
  7. notify        — tell the user the PR is ready for review
  8. approval      — HITL ApprovalOperator; the human approves/rejects in the
                     Airflow UI. Reject fails the run. (No auto-merge.)

Requires Airflow 3.1+ for the HITL ApprovalOperator (built on 3.3.0 here).
"""

from __future__ import annotations

import logging
import sys
from pathlib import Path

import pendulum

from airflow.sdk import dag, task
from airflow.exceptions import AirflowFailException, AirflowSkipException
from airflow.providers.standard.operators.hitl import ApprovalOperator
from airflow.providers.standard.sensors.python import PythonSensor

# The `superreleaser` package is a sibling of this dags/ folder; put the project
# root on sys.path so it imports whether Airflow loads dags from here or elsewhere.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from superreleaser import condaforge, config, gitops, recipe as rcp

log = logging.getLogger("superreleaser.dag")


def _conf(context, key, default=None):
    return (context["dag_run"].conf or {}).get(key, default)


@dag(
    dag_id="cf_release",
    schedule=None,  # triggered manually with conf
    start_date=pendulum.datetime(2026, 1, 1, tz="UTC"),
    catchup=False,
    tags=["superreleaser", "conda-forge"],
    params={"package": "jupyter-ai-acp-client", "version": "", "dry_run": False},
)
def cf_release():
    @task(
        task_display_name="1 · Checkout feedstock",
        doc_md="Sync the `<package>-feedstock` submodule to its remote default "
        "branch so we branch off current state. Fails if the feedstock isn't "
        "checked out locally.",
    )
    def checkout(**context) -> dict:
        package = _conf(context, "package") or context["params"]["package"]
        dry_run = bool(_conf(context, "dry_run", context["params"]["dry_run"])
                       or config.DRY_RUN_DEFAULT)
        fs = config.feedstock_dir(package)
        if not fs.exists():
            raise AirflowFailException(f"feedstock not found: {fs}")
        # Sync to the remote default branch so we branch off current state.
        gitops._run(["git", "fetch", "origin"], cwd=fs, check=False)
        head = gitops._run(
            ["git", "symbolic-ref", "refs/remotes/origin/HEAD"], cwd=fs, check=False
        ) or "refs/remotes/origin/main"
        default_branch = head.rsplit("/", 1)[-1]
        if not dry_run:
            gitops._run(["git", "checkout", default_branch], cwd=fs, check=False)
            gitops._run(["git", "reset", "--hard", f"origin/{default_branch}"], cwd=fs, check=False)
        log.info("feedstock %s on %s (dry_run=%s)", package, default_branch, dry_run)
        return {"package": package, "dry_run": dry_run, "default_branch": default_branch}

    @task(
        task_display_name="2 · Pick version",
        doc_md="Pick the **earliest stable** PyPI version missing from the "
        "feedstock (one bump per PR, conda-forge convention; prereleases "
        "skipped). Skips the run if the feedstock is already current. Override "
        "with the `version` trigger param.",
    )
    def pick_version(ctx: dict, **context) -> dict:
        package = ctx["package"]
        recipe_text = config.recipe_path(package).read_text()
        pypi_project = rcp.pypi_name(recipe_text)
        cur = rcp.current_version(recipe_text)
        forced = _conf(context, "version") or context["params"]["version"]
        target = forced or rcp.earliest_missing_stable(pypi_project, cur)
        if not target:
            raise AirflowSkipException(
                f"{package}: feedstock at {cur} is already current on PyPI"
            )
        log.info("%s: feedstock=%s -> target=%s (pypi=%s)", package, cur, target, pypi_project)
        return {**ctx, "pypi_project": pypi_project, "current": cur, "target": target}

    @task(
        task_display_name="3 · Update recipe",
        doc_md="Set `context.version`, `source.sha256` (from the PyPI sdist), "
        "and rewrite `requirements.run` from the released package's own "
        "metadata. conda-forge names for **new** deps are probed against "
        "anaconda.org, never guessed; unresolvable ones are tracked (not added) "
        "for the draft-PR + comment path. Logs the full `git diff` of the recipe.",
    )
    def update_recipe(ctx: dict) -> dict:
        package, target, pypi_project = ctx["package"], ctx["target"], ctx["pypi_project"]
        recipe_file = config.recipe_path(package)
        fs = config.feedstock_dir(package)
        text = recipe_file.read_text()

        sha = condaforge.sdist_sha256(pypi_project, target)
        if not sha:
            raise AirflowFailException(f"no sdist on PyPI for {pypi_project} {target}")

        existing = rcp.current_run_requirements(text)
        mapping = rcp.map_dependencies(pypi_project, target, existing)
        new_text = rcp.apply_update(text, target, sha, mapping["run"])

        # Always write so we can show a real `git diff`; in dry-run we restore
        # the file afterward so nothing is left changed on disk.
        recipe_file.write_text(new_text)
        diff = gitops.diff(fs, "recipe/recipe.yaml")
        log.info("git diff recipe/recipe.yaml:\n%s", diff or "(no changes)")
        if ctx["dry_run"]:
            gitops._run(["git", "checkout", "--", "recipe/recipe.yaml"], cwd=fs, check=False)
            log.info("[dry-run] reverted recipe on disk (diff shown above only)")

        if mapping["unresolved"]:
            log.warning("UNRESOLVED conda-forge deps (will draft + comment): %s",
                        mapping["unresolved"])
        return {**ctx, "sha256": sha, "diff": diff, **mapping}

    @task(
        task_display_name="4 · Verify on conda-forge",
        doc_md="For every `requirements.run` entry: confirm the conda-forge "
        "package **exists** AND the required **version range resolves** to at "
        "least one real build. Does not hard-fail — entries that don't resolve "
        "are recorded as `unsatisfied` and surfaced in the PR body and the "
        "approval gate, so a human sees the gap.",
    )
    def verify_cf(ctx: dict) -> dict:
        unsatisfied = rcp.verify_run(ctx["run"])
        log.info("verify: %d run deps, %d unresolved names, %d unsatisfied ranges",
                 len(ctx["run"]), len(ctx["unresolved"]), len(unsatisfied))
        for u in unsatisfied:
            log.warning("no conda-forge build satisfies: %s", u)
        return {**ctx, "unsatisfied": unsatisfied}

    @task(
        task_display_name="5 · Open feedstock PR",
        doc_md="Push a branch and open the feedstock PR + `@conda-forge-admin, "
        "please rerender`. Opens as a **draft** (with a comment naming each "
        "unresolvable dependency) if any name was unresolved; a normal PR "
        "otherwise. **Never merges.**",
    )
    def open_pr(ctx: dict) -> dict:
        package, target = ctx["package"], ctx["target"]
        fs = config.feedstock_dir(package)
        branch = f"update-to-{target}"
        title = f"{package} v{target}"
        draft = bool(ctx["unresolved"])  # unresolved dep → draft for human

        body = f"Update `{package}` to `{target}` (sha256 `{ctx['sha256'][:12]}…`).\n\n"
        body += "Run requirements derived from the released package's PyPI metadata.\n"
        if ctx["unsatisfied"]:
            body += "\n⚠️ Version ranges with no matching conda-forge build yet:\n"
            body += "".join(f"- `{u}`\n" for u in ctx["unsatisfied"])

        gitops.branch_and_commit(fs, branch, title, dry_run=ctx["dry_run"])
        gitops.push(fs, branch, dry_run=ctx["dry_run"])
        pr_url = gitops.open_pr(fs, title, body, draft=draft, dry_run=ctx["dry_run"])

        # Rerender is required for conda-forge recipe changes.
        gitops.comment(fs, pr_url, "@conda-forge-admin, please rerender", dry_run=ctx["dry_run"])

        # For each unresolved dep, a comment naming the pypi-name so a human can
        # add the mapping. This is the "track state → comment on failure" path.
        for dep in ctx["unresolved"]:
            gitops.comment(
                fs, pr_url,
                f"⚠️ Could not find a corresponding conda-forge package for "
                f"PyPI dependency **`{dep}`**. This dependency was NOT added to "
                f"`requirements.run`. A maintainer needs to add the correct "
                f"conda-forge name manually before merging.",
                dry_run=ctx["dry_run"],
            )
        log.info("PR: %s (draft=%s)", pr_url, draft)
        return {**ctx, "pr_url": pr_url, "draft": draft}

    def _checks_pass(ctx: dict) -> bool:
        if ctx["dry_run"]:
            logging.getLogger("superreleaser.dag").info("[dry-run] skipping CI wait")
            return True
        state = gitops.pr_checks_state(ctx["pr_url"])
        logging.getLogger("superreleaser.dag").info("CI state: %s", state)
        if state == "FAILURE":
            raise AirflowFailException(f"feedstock CI failed: {ctx['pr_url']}")
        return state == "SUCCESS"

    @task(
        task_display_name="6 · Build approval message",
        doc_md="Assemble the Markdown shown at the approval gate — PR link, "
        "run requirements, and any unresolved/unsatisfied deps.",
    )
    def build_gate_body(ctx: dict) -> str:
        lines = [
            f"### Review conda-forge PR for `{ctx['package']}` v{ctx['target']}",
            "",
            f"**PR:** {ctx['pr_url']}  {'(DRAFT — unresolved deps)' if ctx['draft'] else ''}",
            "",
            "**Run requirements:**",
            *[f"- `{r}`" for r in ctx["run"]],
        ]
        if ctx["unresolved"]:
            lines += ["", "**⚠️ Unresolved deps (not added — fix before merge):**",
                      *[f"- `{u}`" for u in ctx["unresolved"]]]
        if ctx["unsatisfied"]:
            lines += ["", "**⚠️ Ranges with no matching conda-forge build yet:**",
                      *[f"- `{u}`" for u in ctx["unsatisfied"]]]
        lines += ["", "Approve to accept this PR, or Reject to fail the run. "
                  "(This does not auto-merge — merge manually after approval.)"]
        return "\n".join(lines)

    # ---- wiring ----
    c = checkout()
    v = pick_version(c)
    u = update_recipe(v)
    verified = verify_cf(u)
    pr = open_pr(verified)

    wait_for_ci = PythonSensor(
        task_id="wait_for_ci",
        task_display_name="7 · Wait for feedstock CI",
        doc_md="Poll the PR's status checks until they pass or fail "
        "(reschedule mode frees the worker slot between polls). Skipped in "
        "dry-run.",
        python_callable=_checks_pass,
        op_args=[pr],
        mode="reschedule",   # free the slot between polls
        poke_interval=60,
        timeout=60 * 60 * 3,
    )

    gate_body = build_gate_body(pr)
    approval = ApprovalOperator(
        task_id="approval",
        task_display_name="8 · Human approval",
        doc_md="Human-in-the-loop gate. Review the PR in the UI and "
        "**Approve** or **Reject**. Reject fails the run; approve completes it. "
        "Never auto-merges.",
        subject="conda-forge release approval",
        body=gate_body,
        fail_on_reject=True,
    )

    pr >> wait_for_ci >> gate_body >> approval


cf_release()
