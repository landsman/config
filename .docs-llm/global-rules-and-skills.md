# Global rules and skills across harnesses

How one machine-wide conventions setup reaches more than one coding agent, and
why it is shaped this way.

## The shape

One source, symlinked into the places each harness looks, and a one-line pointer
per harness after that. Never a copy.

- **The rules** live in [`shared/.agents/rules/`](../shared/.agents/rules/),
  installed at `~/.agents/rules/` by `make stow`, with `~/.claude/rules` a
  symlink to it. They were under `.claude/` for a while because Claude Code is
  the one client that loads a whole `rules/` directory on its own — but the
  content was never Claude Code's, and a vendor folder as the source of truth is
  the thing this layout exists to avoid. The loader follows the symlink, so the
  one client with a native mechanism keeps it.
- **Claude Code** reads `~/.claude/CLAUDE.md`, which says the rules are in
  `rules/` and Claude Code goes and gets them.
- **The index** is one file at `~/.agents/AGENTS.md`, the neutral home the
  skills already use. Every harness that reads a single global file points at it
  by symlink: `~/.config/opencode/AGENTS.md`, `~/.codex/AGENTS.md`,
  `~/.config/zed/AGENTS.md` and `~/.gemini/GEMINI.md`. Adding the next one is a
  symlink, not a decision.
- **opencode** reads that index and injects the rule *bodies* through
  `instructions: ["~/.agents/rules/*.md"]` in
  [`opencode.json`](../shared/.config/opencode/opencode.json) — `~` is expanded
  and the glob is scanned before any session starts, so adding a rule file picks
  it up with `make stow` and no config change.
- **Codex** reads the same index and gets nothing else: one file, no glob, no
  rules directory, no config key for extra instruction files. So the index opens
  by telling the reader to go and read `~/.agents/rules/*.md` if the bodies are
  not already in context. Codex does follow it — checked with `codex exec`,
  which came back quoting `attribution.md` by path.
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

opencode has no per-path scoping like Claude Code's `paths:`, so every rule
land in every opencode session. Two of them would otherwise wait until a
`.github/` file or a `Makefile` was actually read, and `voice.md` describes a
plugin another client runs. That is roughly two hundred lines of short rules and
buy you the absence of a second copy — a new rule reaches both clients with one
edit. It is the same trade this repo already makes: one source, whatever the
continuation cost.

## `paths:`-scoped rules

A rule with `paths:` frontmatter loads only when Claude Code touches a matching
file, instead of on every turn:

```yaml
---
paths:
  - "**/.github/workflows/*.yml"
  - "**/.github/dependabot.yml"
---
```

The `**/` prefix is not decoration — the glob is matched against the path as
given, so without it the rule misses anything below the repo root. Two rules use
this today: `github-actions.md` and `makefiles.md`.

**A rule earns scoping only when its trigger is a file path *and* breaking it
shows up in a diff.** Everything else overrides a default that would otherwise be
reached for silently, and has to be in context *before* the mistake — which a
scoped rule, by construction, is not. That is the same line that separates a rule
from a skill, drawn one level finer.

**The gap scoping cannot close: writing the file from scratch.** Nothing gets
read first, so nothing matches, so the rule never loads — precisely when it is
needed most. `CLAUDE.md` carries a one-line pointer per scoped rule to cover it;
that row in the index is load-bearing, not a table of contents.

**Claude Code is the only harness that honours it.** opencode injects every rule
body through one glob, and Codex, Zed and Gemini CLI are told to read the whole
directory — so there a scoped rule is simply always on. Scoping saves context in
one harness and costs nothing in the rest, but it also means a scoped rule must
still read correctly when it arrives unprompted.

## A new rule is not live until `make restow`

`~/.agents/rules/` is a real directory of **per-file** symlinks, not a symlinked
directory — that is how GNU stow folds a package. So adding `rules/foo.md` to the
repo changes nothing on the machine until `make restow` links it. Until then the
file is tracked, reviewed, merged, and read by no harness at all.

`linking-work.md` shipped this way: committed, indexed in `CLAUDE.md`, and absent
from `~/.agents/rules/`. Nothing errors — a rule that was never linked and a rule
being ignored look identical from inside a session.

So Claude Code sees a rule only when all three hold: it is stowed, it has no
`paths:` frontmatter, and only then, on every turn. `/context` is the check —
unconditional rules appear under **Memory files**, and the count there is the
one that matters, not the number of files in the repo.

## Adding a harness

Point its global-instructions mechanism at `~/.agents/rules/*.md` if it can take
a glob or a directory. If it reads one file only — the common case — symlink that
path to `~/.agents/AGENTS.md` and let the index tell it to open the rest, which
is what opencode and Codex both do. The content is never forked for it.

Zed and Gemini CLI are the same one-file case as Codex, and are wired up.
Cursor is a third case: it reads *project* rules only, with no global equivalent,
so the machine-wide rules do not reach it. Junie is unresolved — its guidelines
are per-project (`.junie/guidelines.md`) and whether it has a machine-wide
equivalent was not established. Both are gaps, not solved cases.

## MCP servers

The tracked servers from [`mcp-servers.md`](mcp-servers.md) are configured for
opencode too, as `mcp:` entries in `opencode.json`, mirroring the
[`.mcp.json`](../shared/.agents/skills/mcp-servers/.mcp.json) Claude Code reads.
The URLs are the same; the client configuration is the only difference. Rohlík
and Vaadin are remote (`type: remote`), Azure DevOps is the same `sh -c` wrapper
as the plugin, gated on `$AZDO_ORG` being set by `make claude`.