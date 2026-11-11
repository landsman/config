---
paths:
  - "**/.github/workflows/*.yml"
  - "**/.github/workflows/*.yaml"
  - "**/.github/dependabot.yml"
  - "**/.github/dependabot.yaml"
---

# GitHub Actions and Dependabot

Loaded when a file under `.github/` is read, written or edited, which is the only
time any of it applies. `CLAUDE.md` keeps a one-line pointer for the case this
misses: writing one of these files from scratch, where it arrives with the first
write, after the draft.

## Actions stay on the major tag

`uses:` stays on the major tag — `actions/checkout@vN`, whatever major that action
is on, never the 40-character commit SHA the tag points at. Dependabot moves the
major when there is a new one; that is the whole update story.

A scanner will ask for the SHA instead: semgrep's `p/ci` carries
`github-actions-mutable-action-tag`, which fires on every `uses:` line in the repo.
**Do not rewrite the tags to satisfy it.** Forty characters of hash on every line
costs a readable workflow and a readable diff of it forever, and buys defence
against GitHub's own `actions/*` org repointing a release tag at malicious code.

Exclude the rule and say why beside it — `exclude-rules` on the shared semgrep
workflow, or `--exclude-rule` where the scan is local. A third-party action, from
someone whose releases nobody is watching, is the case where this flips; ask then
rather than assuming either way.

## A new push cancels the pull request's old run

Every workflow a `pull_request` triggers carries this, right after `on:`:

```yaml
# A new push to a pull request cancels that PR's run still going: only the newest commit's result counts.
# A push to main or a scheduled scan is never cancelled, so every merged commit and every Monday get a result.
concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
```

Without it, three pushes in a row run three full builds side by side, and the two
older ones only burn runner minutes and fill the checks with results for commits
nobody will merge. Each piece is there for a reason:

- **`github.workflow` in the group** — groups are repo-wide, so without it the
  security scan and the build of one PR would cancel each other.
- **The PR number, falling back to the ref** — every push to one PR lands in the
  same group; a run on `main` or a schedule has no PR and gets the branch's.
- **`cancel-in-progress` only on `pull_request`** — a run on `main`, a schedule or
  a `workflow_dispatch` queues instead. A cancelled build on `main` is a merged
  commit with no result, and a cancelled Monday scan is a week without one.
- **A deploy never cancels.** `cancel-in-progress: false` on its own group, so the
  second deploy waits for the first instead of killing it halfway.

**A reusable workflow (`on: workflow_call` only) does not set it.** It runs in the
caller's context, so `github.workflow` is the caller's name: the same group, and the
called workflow cancels the caller that started it (GitHub's own note, in
`reusing-workflow-configurations.md`). The caller's `concurrency` covers it.

## A change to Markdown alone runs nothing

Every `push` and `pull_request` trigger carries `paths-ignore: ['**.md']`, the
security scan included. A README edit has no job that reads it, and a run for it is
minutes of runners and a page of checks for nothing:

```yaml
on:
  push:
    branches: [main]
    paths-ignore: ['**.md']
  # A change to Markdown alone runs nothing; the Monday run still scans the whole tree.
  pull_request:
    types: [opened, synchronize, reopened, ready_for_review]
    paths-ignore: ['**.md']
  schedule:
    - cron: '0 6 * * 1'
```

A commit that touches anything else as well runs in full: `paths-ignore` skips a
run only when *every* changed file matches. Add other files no job reads
(`LICENSE`, `.gitignore`) when a repo has them changing often; do not grow the list
to things a build does read, a `.properties` or a template.

- **The secret scan still catches a doc.** Semgrep's `p/secrets` reads Markdown, so a
  token pasted into one is found by the `schedule` run, which scans the whole tree.
  That is why a security workflow keeps its `schedule` when it gains the filter.
- **A workflow whose job reads Markdown** (a link check, a docs site build) filters
  the other way: `paths: ['**.md', 'docs/**']`.
- **A required status check and a path filter do not mix.** A workflow skipped by a
  filter leaves its check *Pending*, and a pull request that requires it cannot be
  merged (`content/actions/how-tos/manage-workflow-runs/skip-workflow-runs.md`). When
  a branch requires checks, the workflow runs and a first `changes` job decides
  instead: a skipped job reports a result, a workflow that never started does not.
  Check with `gh api repos/<owner>/<repo>/branches/main/protection` before adding
  the filter.
- GitHub diffs a pull request three-dot, from where it last synced with the base,
  so the filter sees exactly the branch's files. **Forgejo does not**; see
  `forgejo-workflows.md`.

## Dependabot gets a cooldown

Every `updates:` entry carries one. **3 to 7 days, and 7 unless there is a reason:**

```yaml
    cooldown:
      default-days: 7
```

A compromised package is typically found and yanked within days of publication, and
the point of automating a bump is that nobody reads the diff — so the automation
must not be the thing that races the registry. Below 3 there is no soak worth the
name; above 7 the bumps pile up and get merged unread, which is the same failure
by a slower route. It costs nothing in security response: cooldown applies to
version updates only, and a Dependabot security update for a CVE still arrives at
once.

Two things to know before picking 3 over 7:

- Semgrep's `dependabot-missing-cooldown` (in `p/ci`) flags **any value under 7**,
  not just a missing block. Choosing 3 in a repo that runs that pack means also
  excluding that rule, and a suppressed rule needs a reason written next to it.
- `semver-major-days` / `-minor-days` / `-patch-days` exist, but not for every
  ecosystem — `github-actions` and `docker` take `default-days` only. Reach for
  them when one repo genuinely wants majors to soak longer, not by default.

Set `commit-message.prefix: deps` on every entry too, so Dependabot writes this
account's convention instead of its own `build(deps):`.

## Where the docs live

GitHub's own Actions documentation is `github/docs`, sparse-cloned to
`~/projects/github/github/docs` — 8 MB of `content/actions`, not the whole site.
Grep it instead of recalling syntax:

    rg -n "concurrency" ~/projects/github/github/docs/content/actions/reference/workflows-and-actions/workflow-syntax.md

- `content/actions/reference/workflows-and-actions/workflow-syntax.md` — the full
  `on:` / `jobs:` / `steps:` reference
- `content/actions/reference/workflows-and-actions/contexts.md` — `github.*`,
  `needs.*`, `secrets.*`, and which of them exist where
- `content/actions/reference/runners/` — hosted labels and what is on them

Pages transclude `{% data reusables.… %}` snippets, so `data/` is in the checkout
too; anything outside `content/actions` is deliberately absent. Not on this
machine, or stale? `make -C ~/projects/landsman/config agent-docs` clones it and
fast-forwards it on a re-run — it owns the sparse paths so this file does not.

**The docs are not the version check.** They describe the syntax, not which major
an action is on — that stays `gh api repos/<owner>/<action>/releases/latest`.
