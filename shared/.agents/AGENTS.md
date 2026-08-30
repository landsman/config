# Global rules

Personal conventions that apply to every coding-agent session on this machine,
whatever tool is running it. The text is agent-neutral: each harness reads the
same rules from the same home.

**If the nine rule bodies are not already in your context, read
`~/.claude/rules/*.md` now.** Whether they arrive on their own depends on the
harness, and the table below is an index, not the rules themselves.

The single source of those bodies is `~/.claude/rules/*.md`, tracked as
[`shared/.claude/rules/`](../.claude/rules/) in this repo and symlinked into the
home directory by `make stow`. The folder keeps Claude Code's name because that
is the client which loads a whole `rules/` directory on its own; nothing is
duplicated for the others.

How each harness gets here:

- **Claude Code** loads `~/.claude/rules/` itself, and never reads this file.
- **opencode** reads this file as `~/.config/opencode/AGENTS.md` and injects the
  rule bodies through `instructions: ["~/.claude/rules/*.md"]` in the
  `opencode.json` beside it — so they are already in context, not references.
- **Codex** reads this file as `~/.codex/AGENTS.md` and takes one file only: no
  glob, no rules directory, no config key for extra instruction files. It has to
  open the rule files itself, which is what the instruction above is for.
- **Zed** reads it as `~/.config/zed/AGENTS.md`, injected into every project's
  prompt. One file, same as Codex.
- **Gemini CLI** reads it as `~/.gemini/GEMINI.md` — the filename is the only
  difference, and a symlink settles that without touching `contextFileName` in
  its `settings.json`.

Those are all symlinks to this one file, which lives at `~/.agents/AGENTS.md` —
the same neutral home the skills use. A harness that reads a single global file
needs a symlink and nothing else; only opencode needed a config line, because it
is the only one that can inject the bodies.

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

The one thing this file adds is the statement that the nine are authoritative
everywhere, and the pointer for any harness that does not inject them.
