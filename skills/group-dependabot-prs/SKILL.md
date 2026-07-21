---
name: group-dependabot-prs
description: Consolidate a repo's separate Dependabot PRs into ONE grouped PR by installing a grouping config, then closing the pre-existing ungrouped PRs. Use when a repo has many individual Dependabot PRs (one per dependency) and you want them collapsed into a single grouped PR.
---

# Group Dependabot PRs into a single PR

Takes one argument: a GitHub repo (`owner/name`). It installs a `.github/dependabot.yml`
that groups all npm updates into one PR per run, verifies the config validates, closes
the pre-existing ungrouped Dependabot PRs, merges the config, and confirms Dependabot
re-opens a single grouped PR.

## When to use

A repo has many separate Dependabot PRs (one per dependency bump) and you want them
collapsed into a single grouped PR going forward. Works whether or not the repo already
has a `.github/dependabot.yml`.

## Key facts (read before starting)

- **Dependabot groups by *update type*.** It NEVER mixes version updates and security
  updates in the same PR, and never mixes package ecosystems. A group's `applies-to`
  key selects which type it targets (`version-updates` or `security-updates`), and a
  single group targets exactly one type.
- **Consequence:** to group everything you need **two** groups both matching `"*"` —
  one `applies-to: version-updates`, one `applies-to: security-updates`. A config with
  only the default group (which is `version-updates`) will NOT group existing
  security-update PRs. Check what the repo's existing PRs are before assuming:

  ```bash
  gh pr list --repo <repo> --author "app/dependabot" --state open \
    --json number,title,headRefName
  ```

  Dependabot security-update PRs run *without* any config; their branch names look like
  `dependabot/npm_and_yarn/<pkg>-<ver>` and titles say "Bump <pkg> …". If they're
  security updates, the `security-updates` group is mandatory.

## Workflow

### 1. Write the grouping config

Write `.github/dependabot.yml` in the target repo (from inside `dev/<repo>` in a
workspace). Handle both cases: the repo may have no existing config, or an existing one
you extend. This config groups **all** npm updates (both version and security) into one
PR each:

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

Group identifiers must start and end with a letter (letters, `_`, `-` allowed between).
`patterns: ["*"]` matches every dependency. The `groups:` key sits under the
`package-ecosystem` entry, at the same level as `directory` and `schedule`.

> Do a quick web check of GitHub's "Configuration options for the dependabot.yml file"
> and "Configuring Dependabot security updates" docs to confirm syntax hasn't changed —
> the `applies-to` split between version and security updates is the part that bites.

### 2. Open a draft PR for the config

Follow `skills/open-pr` conventions. In a workspace:

```bash
just dev ensure-fork <repo-name>
(cd dev/<repo> && git add -A && git commit -m "Add dependabot config to group npm updates into a single PR")
(cd dev/<repo> && git push -u fork HEAD && gh pr create --draft --title "Group Dependabot npm updates into a single PR" --body "<short body>")
```

Then label it for the changelog (best-effort). This repo type usually has a
`dependencies` label (fits a dependency-file change); fall back to `maintenance`:

```bash
(cd dev/<repo> && gh label list)
(cd dev/<repo> && gh pr edit <pr-number> --add-label "dependencies")
```

Note: the repo's `enforce-label` CI check will FAIL until a label is applied — labeling
is required here, not merely best-effort, for CI to go green.

### 3. Verify the config validates

When a `.github/dependabot.yml` changes, GitHub's Dependabot app runs a config
validation check. Its display name is **`dependabot`** (the check-suite app slug is
`dependabot`; the check-run name is `dependabot`). Confirm it PASSES.

The check does NOT always appear immediately — it can lag the github-actions checks by
several minutes, and on some repos may not surface as a PR status at all. Poll for it:

```bash
HEAD=$(git -C dev/<repo> rev-parse HEAD)
REPO=<repo>
# look for a dependabot check-run OR a dependabot check-suite
gh api repos/$REPO/commits/$HEAD/check-runs \
  --jq '.check_runs[] | select(.name|test("dependabot";"i")) | "\(.name)\t\(.status)\t\(.conclusion)"'
gh api repos/$REPO/commits/$HEAD/check-suites \
  --jq '.check_suites[] | select(.app.slug|test("dependabot";"i")) | "\(.app.slug)\t\(.status)\t\(.conclusion)"'
```

`gh pr checks <n> --repo <repo>` shows it too once it appears. A `conclusion` of
`success` (or a green suite) means the YAML is valid. If it reports failure, the error
message names the offending key — fix the config and push again.

**Observed reality (fork PRs):** when the config PR comes from a *fork* (the normal
workspace flow — you push to `dev/<repo>`'s `fork` remote), the Dependabot
config-validation check does NOT appear as a PR status. Dependabot validates on
branches it scans within the upstream repo, and doesn't run its validation app on fork
PRs. Don't wait the full window for a check that will never come. Instead:

1. Validate the YAML locally. `pyyaml` may not be in the workspace venv — use whatever
   python has it (e.g. the micromamba base): `/path/to/python -c "import yaml;
   yaml.safe_load(open('dev/<repo>/.github/dependabot.yml'))"`.
2. Confirm structure matches the docs (two groups, correct `applies-to`, `patterns`).
3. Confirm the github-actions CI checks on the PR are green (`build`, `test_isolated`,
   `check_release`, `enforce-label`, `Check Links`).

That's sufficient to proceed. The real validation happens the moment the config lands
on the default branch: if it were malformed, Dependabot would surface an error on the
repo's default branch and simply not regroup — which step 5's poll would catch as a
timeout. A well-formed config that matches the docs is safe to merge.

### 4. Close the old PRs, then merge the config

**Order matters: close the ungrouped PRs FIRST, then merge the config.** Before
closing, record the pre-existing PR numbers so you can later tell a genuinely new
grouped PR apart from these.

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

> The config PR is *meant* to be merged as part of this run — it's not left as a draft.
> This is the one exception to the "PRs stay draft" rule, because merging the config is
> what makes Dependabot regroup.

### 5. Confirm Dependabot re-opens a single grouped PR

After the config merges, Dependabot re-runs on its own and should open ONE new grouped
PR. Poll for a NEW dependabot PR (a number NOT in the pre-existing set from step 4) for
**up to 15 minutes**:

```bash
OLD="71 72 73 74 75 76 77 79 80"   # the pre-existing set
REPO=<repo>
for i in $(seq 1 30); do   # 30 × 30s = 15 min
  cur=$(gh pr list --repo $REPO --author "app/dependabot" --state open --json number --jq '.[].number')
  new=$(comm -13 <(echo "$OLD" | tr ' ' '\n' | sort) <(echo "$cur" | tr ' ' '\n' | sort))
  if [ -n "$new" ]; then echo "NEW grouped PR: $new"; break; fi
  sleep 30
done
```

The new grouped PR's title/branch names the group (e.g. `npm-security-updates`) rather
than a single package. **Record how long it took** — the wall-clock from merge to the
new PR appearing is the number worth reporting.

**If NO new PR appears within 15 minutes:** MESSAGE THE USER — do NOT try to
force-trigger Dependabot yourself:

```bash
cmux notify --title "Stuck: <ws>" --body "Dependabot hasn't re-opened a grouped PR 15 min after merging the grouping config on <repo>. Config PR #<n> merged, old PRs closed. Need to figure out the retrigger together."
```

We'll pick up the manual retrigger together (Insights → Dependabot → "Check for updates",
or re-run via the Dependabot section of the repo's settings).

## Notes

- The existing PRs on a repo that has *no* config are almost always **security**
  updates — that's why the `security-updates` group is not optional. Verify with
  `gh pr list … --json headRefName,title` before writing the config.
- Dependabot never groups across ecosystems or across update types; one group = one
  ecosystem × one update type. For npm-only repos the two-group config above is enough.
- The validation check is named `dependabot` (app slug `dependabot`), distinct from the
  repo's github-actions checks (`build`, `check_release`, `enforce-label`, `Check Links`).
  It can lag behind the actions checks — poll, don't assume it's missing.
- `enforce-label` will hold CI red until you apply a label — do the labeling in step 2,
  don't treat it as optional here.
- Grouped **security** updates also require the repo to have Dependabot security updates
  enabled (`gh api repos/<repo>/automated-security-fixes` → `"enabled": true`).
