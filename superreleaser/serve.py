"""serve() entrypoint — registers the three fixed deployments and executes runs.

This is a STANDING service brought up by `just start-superreleaser`. It talks to
the already-running `prefect server start` (it never owns the server). It
registers the deployments once and then blocks, executing any runs the server
schedules — including resuming gated runs after a human approves in the UI.

    python -m superreleaser.serve
"""

from __future__ import annotations

from prefect import serve

from .flows import release_batch, release_feedstock, release_subpackage


def main() -> None:
    subpackage = release_subpackage.to_deployment(
        name="release-subpackage",
        description="Release one Jupyter AI subpackage: prep → gate → publish "
        "→ PyPI → (stable) conda-forge.",
        tags=["superreleaser"],
    )
    feedstock = release_feedstock.to_deployment(
        name="release-feedstock",
        description="conda-forge leg: update recipe → PR → CI → gate → merge.",
        tags=["superreleaser"],
    )
    batch = release_batch.to_deployment(
        name="release-batch",
        description="Orchestrate a release plan: sequential waves of concurrent "
        "subpackage releases.",
        tags=["superreleaser"],
    )
    serve(subpackage, feedstock, batch)


if __name__ == "__main__":
    main()
