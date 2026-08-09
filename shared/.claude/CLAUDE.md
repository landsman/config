Every rule lives in [`rules/`](rules/), one file each. This file is the index.

A rule there loads unconditionally unless it declares `paths:` frontmatter,
which scopes it to the files it is about. A rule earns that scoping only when
its trigger is a file path *and* breaking it shows up in a diff — GitHub Actions
is the only one so far. The rest override a default I would otherwise fall back
to, so they have to be in context before the mistake, not after.

| Rule | Applies when |
|------|--------------|
| [Reporting data and metrics](rules/reporting-data.md) | a number gets reported — a query, a benchmark, a count |
| [Localisation](rules/localisation.md) | user-facing text gets written — a label, an error, an email |
| [Attribution](rules/attribution.md) | anything leaves the machine or gets committed |
| [Commit messages](rules/commit-messages.md) | writing a commit |
| [Git history](rules/git-history.md) | amend, squash, rebase, force-push |
| [GitHub Actions](rules/github-actions.md) | writing under `.github/` — scoped, loads itself |
| [Voice](rules/voice.md) | background, not a rule: the plugin that reads answers aloud |

The folder name is not a preference: `rules/` and `CLAUDE.md` are the only two
things Claude Code loads on its own. A folder named anything else is inert
unless this file imports it with `@`. After changing the layout, check `/context`
— unconditional rules show up under **Memory files**, and one that quietly
stopped loading looks exactly like one being ignored.
