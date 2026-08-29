# Global rules

Personal conventions that apply to every coding-agent session on this machine,
whatever tool is running it. The text is agent-neutral: each harness reads the
same rules from the same home.

The single source of the rule bodies is [`~/.claude/rules/*.md`](~/.claude/rules/),
tracked as [`shared/.claude/rules/`](../../../shared/.claude/rules/) in this
repo and symlinked into the home directory by `make stow`. Claude Code loads
them through its `rules/` directory; opencode loads the same files through the
`instructions` field of the `opencode.json` next to this file. A new harness
does the same thing with whatever its config calls the pointer — the content is
never duplicated for it.

| Rule | Applies when |
|------|--------------|
| [Where the repos live](~/.claude/rules/where-repos-live.md) | finding a repo on disk, and which ones may be named in public |
| [Reporting data and metrics](~/.claude/rules/reporting-data.md) | a number gets reported — a query, a benchmark, a count |
| [Localisation](~/.claude/rules/localisation.md) | user-facing text gets written — a label, an error, an email |
| [Attribution](~/.claude/rules/attribution.md) | anything leaves the machine or gets committed |
| [Commit messages](~/.claude/rules/commit-messages.md) | writing a commit |
| [Git history](~/.claude/rules/git-history.md) | amend, squash, rebase, force-push |
| [GitHub Actions](~/.claude/rules/github-actions.md) | writing under `.github/` |
| [Makefiles](~/.claude/rules/makefiles.md) | writing a `Makefile` |
| [Voice](~/.claude/rules/voice.md) | background, not a rule: the plugin that reads answers aloud |

All nine are already in context — opencode injects them from the `instructions`
glob at session start, so they are not lazy-loaded references. The one thing
this file adds is the statement that they are authoritative everywhere, and the
pointer for any harness not using opencode's mechanism.