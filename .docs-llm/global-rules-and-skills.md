# Global rules and skills across harnesses

How one machine-wide conventions setup reaches more than one coding agent, and
why it is shaped this way.

## The shape

One source, symlinked into the places each harness looks, and a one-line pointer
per harness after that. Never a copy.

- **The rules** live in
  [`shared/.claude/rules/`](../shared/.claude/rules/), symlinked to
  `~/.claude/rules/` by `make stow`. The content is portable Markdown; the
  folder is named after Claude Code only because that is the client which loads
  a whole `rules/` directory on its own (scoping the two file-triggered rules
  with `paths:` frontmatter). Staying there is what keeps the connection
  working, so the origin has to follow.
- **Claude Code** reads `~/.claude/CLAUDE.md`, which says the rules are in
  `rules/` and Claude Code goes and gets them.
- **opencode** reads `~/.config/opencode/AGENTS.md` (a general index that is
  not vendor-specific) and injects the rule *bodies* through
  `instructions: ["~/.claude/rules/*.md"]` in
  [`opencode.json`](../shared/.config/opencode/opencode.json) — `~` is expanded
  and the glob is scanned before any session starts, so adding a rule file picks
  it up with `make stow` and no config change.
- **Skills** live in `~/.agents/skills/`, and `~/.claude/skills` is a symlink to
  it. `SKILL.md` is the portable format, so the split was never about content —
  it is that each client hardcodes a different directory. opencode scans both
  and would have been happy either way; Codex scans `.agents/skills` only, walking
  up from the working directory, and has no config key to add a path. Claude Code
  scans `~/.claude/skills` only. So the neutral path holds the files and the
  vendor path points at it, the same trade as `AGENTS.md` with a `CLAUDE.md`
  symlink beside it. `make stow` builds that layout and moves anything already
  sitting in `~/.claude/skills` across; it is a no-op once the link exists.
  Discovery does follow the symlink — checked on both clients, not assumed.

## The cost of the glob

opencode has no per-path scoping like Claude Code's `paths:`, so all nine rules
land in every opencode session. Two of them would otherwise wait until a
`.github/` file or a `Makefile` was actually read, and `voice.md` describes a
plugin another client runs. That is roughly two hundred lines of short rules and
buy you the absence of a second copy — a new rule reaches both clients with one
edit. It is the same trade this repo already makes: one source, whatever the
continuation cost.

## Adding a harness

Point its global-instructions mechanism at `~/.claude/rules/*.md`, or at the
opencode `AGENTS.md` when the harness only reads one file (Codex, Cursor and the
other `AGENTS.md` consumers read that one directly). The content is never forked
for it.

## MCP servers

The tracked servers from [`mcp-servers.md`](mcp-servers.md) are configured for
opencode too, as `mcp:` entries in `opencode.json`, mirroring the
[`.mcp.json`](../shared/.agents/skills/mcp-servers/.mcp.json) Claude Code reads.
The URLs are the same; the client configuration is the only difference. Rohlík
and Vaadin are remote (`type: remote`), Azure DevOps is the same `sh -c` wrapper
as the plugin, gated on `$AZDO_ORG` being set by `make claude`.