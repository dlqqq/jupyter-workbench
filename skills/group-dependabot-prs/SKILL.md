---
name: group-dependabot-prs
description: Consolidate a repo's separate Dependabot PRs into ONE grouped PR by installing a grouping config, then closing the pre-existing ungrouped PRs. Use when a repo has many individual Dependabot PRs (one per dependency) and you want them collapsed into a single grouped PR.
---

# Group Dependabot PRs into a single PR

Takes one argument: a GitHub repo (`owner/name`). It installs a `.github/dependabot.yml`
that groups npm updates into one PR per run, closes the pre-existing ungrouped Dependabot
PRs, merges the config, and confirms Dependabot re-opens a single grouped PR.

## When to use

A repo has many separate Dependabot PRs (one per dependency bump) and you want them
collapsed into a single grouped PR going forward. Works whether or not the repo already
has a `.github/dependabot.yml`.

## Decide the scope FIRST: security-only or everything?

This is the single most important decision, and it changes the config. Ask the user
which they want — don't assume.

- **Security-only** (common intent): Dependabot opens a grouped PR *only* when a
  security advisory affects a dependency. No routine "bump X to latest-in-range" churn.
- **Everything**: also open routine version-update PRs (grouped) on a schedule.

**Dependabot groups by *update type*.** It NEVER mixes version updates and security
updates in the same PR, and never mixes package ecosystems. A group's `applies-to` key
selects which type it targets (`version-updates` or `security-updates`); one group
targets exactly one type. So "group everything" needs **two** groups.

Check what the repo's *current* Dependabot PRs are before writing anything — a repo with
no config almost always has **security** PRs (they run without a config, off Dependabot
alerts):

```bash
gh pr list --repo <repo> --author "app/dependabot" --state open --json number,title,headRefName
```

### Config A — security-only (recommended default)

`open-pull-requests-limit: 0` is the documented way to disable routine version-update
PRs while keeping security updates. Security updates run off Dependabot alerts regardless
of this limit or the schedule.

```yaml
version: 2
updates:
  - package-ecosystem: "npm"
    directory: "/"
    # `schedule.interval` is a REQUIRED key (config fails validation without it),
    # but it only governs version updates — which are disabled below — so its
    # value is inert here. Security updates are triggered by Dependabot alerts.
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 0
    groups:
      npm-security-updates:
        applies-to: security-updates
        patterns:
          - "*"
```

### Config B — group everything (version + security)

```yaml
version: 2
updates:
  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "weekly"
    groups:
      npm-version-updates:
        applies-to: version-updates
        patterns:
          - "*"
      npm-security-updates:
        applies-to: security-updates
        patterns:
          - "*"
```

Group identifiers must start and end with a letter (letters, `_`, `-` between).
`patterns: ["*"]` matches every dependency. `groups:` sits under the `package-ecosystem`
entry, at the same level as `directory` and `schedule`.

> Do a quick web check of GitHub's "Configuration options for the dependabot.yml file"
> and "Configuring Dependabot security updates" docs to confirm syntax — the `applies-to`
> split and `open-pull-requests-limit: 0` semantics are the parts that bite.

## Workflow

### 1. Write the config

Write `.github/dependabot.yml` in the target repo (from inside `dev/<repo>` in a
workspace). Handle both the create and update cases.

### 2. Open a draft PR for the config

Follow `skills/open-pr` conventions:

```bash
just dev ensure-fork <repo-name>
(cd dev/<repo> && git add -A && git commit -m "Add dependabot config to group npm security updates")
(cd dev/<repo> && git push -u fork HEAD && gh pr create --draft --title "Group Dependabot npm updates into a single PR" --body "<short body>")
```

Then label it. This repo type usually has a `dependencies` label (fits a dependency-file
change); fall back to `maintenance`:

```bash
(cd dev/<repo> && gh label list)
(cd dev/<repo> && gh pr edit <pr-number> --add-label "dependencies")
```

Note: the repo's `enforce-label` CI check FAILS until a label is applied — labeling is
required for CI to go green, not optional.

### 3. Verify the config validates

GitHub's Dependabot app *can* run a config-validation check when `.github/dependabot.yml`
changes (check-run / check-suite app slug `dependabot`):

```bash
HEAD=$(git -C dev/<repo> rev-parse HEAD)
REPO=<repo>
gh api repos/$REPO/commits/$HEAD/check-runs \
  --jq '.check_runs[] | select(.name|test("dependabot";"i")) | "\(.name)\t\(.status)\t\(.conclusion)"'
gh api repos/$REPO/commits/$HEAD/check-suites \
  --jq '.check_suites[] | select(.app.slug|test("dependabot";"i")) | "\(.app.slug)\t\(.status)\t\(.conclusion)"'
```

**Observed reality (fork PRs):** when the config PR comes from a *fork* (the normal
workspace flow — you push to `dev/<repo>`'s `fork` remote), this check does NOT appear.
Dependabot doesn't run its validation app on fork PRs. Don't wait for a check that never
comes. Instead:

1. Validate the YAML locally. `pyyaml` may not be in the workspace venv — use a python
   that has it (e.g. the micromamba base):
   `/path/to/python -c "import yaml; yaml.safe_load(open('dev/<repo>/.github/dependabot.yml'))"`.
2. Confirm structure matches the docs.
3. Confirm the github-actions CI checks on the PR are green.

A well-formed config that matches the docs is safe to merge; the real validation happens
when it lands on the default branch.

### 4. Close the old PRs, then merge the config

**Order matters: close the ungrouped PRs FIRST, then merge the config.** Record the
pre-existing PR numbers so you can later tell a genuinely new grouped PR apart.

```bash
# record the current set (these are the OLD ones)
gh pr list --repo <repo> --author "app/dependabot" --state open --json number --jq '.[].number'

# close them all
for n in <the numbers above>; do
  gh pr close $n --repo <repo> --comment "Superseded by grouped Dependabot config (#<config-pr>)."
done

# then merge the config PR (mark ready first if it's a draft)
gh pr ready <config-pr> --repo <repo>
gh pr merge <config-pr> --repo <repo> --squash
```

> The config PR is *meant* to be merged as part of this run — not left as a draft. This
> is the one exception to the "PRs stay draft" rule; merging it is what makes Dependabot
> regroup.

### 5. Get Dependabot to re-open the grouped PR

Poll for a NEW dependabot PR (a number NOT in the set from step 4) for **up to 15
minutes**:

```bash
OLD="71 72 73 ..."   # the pre-existing set from step 4
REPO=<repo>
for i in $(seq 1 30); do   # 30 × 30s = 15 min
  cur=$(gh pr list --repo $REPO --author "app/dependabot" --state open --json number --jq '.[].number')
  new=$(comm -13 <(echo "$OLD" | tr ' ' '\n' | sort) <(echo "$cur" | tr ' ' '\n' | sort))
  if [ -n "$new" ]; then echo "NEW grouped PR: $new"; break; fi
  sleep 30
done
```

**Merging the config does NOT reliably trigger an immediate run** — it registers the
config and queues the next *scheduled* run. Expect the 15-min poll to time out. The
retrigger path depends on scope, and this is where the naive instinct is wrong:

- **The Insights → Dependency graph → Dependabot tab (and its "Check for updates" button)
  is for VERSION updates only.** For a security-only config it shows "not configured" and
  has no useful button — that is EXPECTED, not a bug.
- **To force grouped SECURITY updates:** go to **Settings → Advanced Security → Dependabot
  → "Grouped security updates" → Enable** (org-level: Global settings). GitHub's docs:
  *"When grouped security updates are first enabled, Dependabot will immediately try to
  create grouped pull requests… closing old pull requests and opening new ones."* That is
  the on-demand trigger.
- **Alternative:** `@dependabot recreate` on an existing (re-opened) Dependabot PR rebuilds
  it against the current config.

**Do NOT force-trigger silently.** If the poll times out, MESSAGE THE USER and hand off
the retrigger — it's a UI action (the Advanced Security toggle) you can't do via `gh`:

```bash
cmux notify --title "Stuck: <ws>" --body "Dependabot hasn't re-opened a grouped PR 15 min after merging the config on <repo>. Config merged, old PRs closed. Retrigger is a UI action: Settings -> Advanced Security -> Grouped security updates -> Enable. Let's do it together."
```

## Notes

- **Confirm security updates are enabled** on the repo, or the security group never fires:
  `gh api repos/<repo>/automated-security-fixes` → `"enabled": true`.
- **`github.actor` vs PR author (if you ever touch Dependabot-reactive workflows):**
  `github.actor` is whoever last triggered a run, not the PR author — gate on
  `github.event.pull_request.user.login == 'dependabot[bot]'` instead.
- **Dependabot secret store is separate from Actions secrets.** A run only sees Dependabot
  secrets when *Dependabot itself* triggered it; any human/bot re-trigger uses the Actions
  store. Dependabot has secrets only (no variables). Same `secrets.` syntax, different
  store.
- **Lockfile drift after a bump.** For Yarn Berry repos (`jlpm`), Dependabot's updater can
  produce a `yarn.lock` that fails CI's frozen install. Fix it by hand on the PR branch —
  `jlpm install` (mutable locally) then commit `yarn.lock`. We tried automating this with
  a Dependabot-reactive workflow that regenerates and pushes the lockfile, and **abandoned
  it**: the secret-store-depends-on-trigger rule, the workflow re-triggering itself after
  its own push, and needing a non-`GITHUB_TOKEN` identity to re-run CI made it more trouble
  than a 30-second manual fix. Do NOT re-attempt the auto-fix workflow without a clear
  reason.
- **Build breakage from the bumps themselves** is a separate problem no config or lockfile
  step fixes — the grouped PR's `build` can fail because an updated dependency broke the
  build. That needs human/code triage of which update is responsible.
- Dependabot never groups across ecosystems or update types; one group = one ecosystem ×
  one update type. For npm-only repos the configs above are enough.
