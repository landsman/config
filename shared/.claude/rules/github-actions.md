---
paths:
  - "**/.github/workflows/*.yml"
  - "**/.github/workflows/*.yaml"
  - "**/.github/dependabot.yml"
  - "**/.github/dependabot.yaml"
---

# GitHub Actions and Dependabot

Loaded only when something under `.github/` is being read, which is the only
time any of it applies. `CLAUDE.md` keeps a one-line pointer for the case this
misses: writing one of these files from scratch, where there is nothing to read
first.

## Actions stay on the major tag

`uses:` stays on the major tag — `actions/checkout@vN`, whatever major that
action is on, never the 40-character commit SHA the tag points at. Dependabot
moves the major when there is a new one; that is the whole update story.

A scanner will ask for the SHA instead: semgrep's `p/ci` carries
`github-actions-mutable-action-tag`, which fires on every `uses:` line in the
repo. **Do not rewrite the tags to satisfy it.** Forty characters of hash on
every line costs a readable workflow and a readable diff of it forever, and buys
defence against GitHub's own `actions/*` org repointing a release tag at
malicious code.

Exclude the rule and say why beside it — `exclude-rules` on the shared semgrep
workflow, or `--exclude-rule` where the scan is local. A third-party action,
from someone whose releases nobody is watching, is the case where this flips;
ask then rather than assuming either way.

## Dependabot gets a cooldown

Every `updates:` entry carries one. **3 to 7 days, and 7 unless there is a
reason:**

```yaml
cooldown:
  default-days: 7
```

A compromised package is typically found and yanked within days of publication,
and the point of automating a bump is that nobody reads the diff — so the
automation must not be the thing that races the registry. Below 3 there is no
soak worth the name; above 7 the bumps pile up and get merged unread, which is
the same failure by a slower route. It costs nothing in security response:
cooldown applies to version updates only, and a Dependabot security update for a
CVE still arrives at once.

Two things to know before picking 3 over 7:

- Semgrep's `dependabot-missing-cooldown` (in `p/ci`) flags **any value under
  7**, not just a missing block. Choosing 3 in a repo that runs that pack means
  also excluding that rule, and a suppressed rule needs a reason written next to
  it.
- `semver-major-days` / `-minor-days` / `-patch-days` exist, but not for every
  ecosystem — `github-actions` and `docker` take `default-days` only. Reach for
  them when one repo genuinely wants majors to soak longer, not by default.

Set `commit-message.prefix: deps` on every entry too, so Dependabot writes this
account's convention instead of its own `build(deps):`.
