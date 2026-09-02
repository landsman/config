# Global rules

Personal conventions that apply to every coding-agent session on this machine,
whatever tool is running it. The text is agent-neutral: each harness reads the
same rules from the same home.

**If the rule bodies are not already in your context, read
`~/.agents/rules/*.md` now.** Whether they arrive on their own depends on the
harness; this file names none of them, so the glob is the whole list.

The single source of those bodies is `~/.agents/rules/*.md`, tracked as
[`shared/.agents/rules/`](rules/) in this repo and symlinked into the home
directory by `make stow`. They sit beside this file and the skills, under
`.agents/`, because they belong to whatever agent is running — not to the one
whose folder they used to live in.

How each harness gets here:

- **Claude Code** loads `~/.claude/rules/` itself, and never reads this file.
  That path is a symlink to `~/.agents/rules/`; the loader follows it.
- **opencode** reads this file as `~/.config/opencode/AGENTS.md` and injects the
  rule bodies through `instructions: ["~/.agents/rules/*.md"]` in the
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

The one thing this file adds is the statement that they are authoritative
everywhere, and the pointer for any harness that does not inject them.

**There is deliberately no index table here.** One lived in this file and a
second in `~/.claude/CLAUDE.md`, and the two drifted: a rule was added to one
and not the other, which reads exactly like a rule being ignored. The table
earns its place in `CLAUDE.md`, where it can carry per-rule notes about `paths:`
scoping that are true for Claude Code and false for every harness reading this
file. Here it bought nothing the glob above does not already say.
