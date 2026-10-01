# What of the agent config is tracked

Which parts of `~/.claude` and `~/.agents` come from this repo, and the one rule `settings.json` has to keep.

- **`~/.claude` is mostly runtime state** — sessions, caches, history. Only
  `CLAUDE.md`, `settings.json`, `voice.local.md` and the
  `.agents/skills/mcp-servers/`
  plugin — which is how the [MCP servers](../.docs-llm/mcp-servers.md) get tracked,
  since neither `settings.json` nor `~/.claude.json` can hold them — are tracked,
  all in `shared/`; `--no-folding` keeps the directory real so nothing the tool writes
  lands here. `voice.local.md` is the odd one: the voice plugin rewrites it in
  place when you toggle voice, so a diff there is usually a toggle rather than a
  change worth committing.
- **The global rules are not Claude Code's** — they live in `shared/.agents/rules/`,
  installed at `~/.agents/rules/`, beside the shared `AGENTS.md` index and the
  skills. `~/.claude/rules` is a symlink to them, so Claude Code keeps the one
  native mechanism anyone has for loading a whole rules directory. Every other
  client reads the index at `~/.agents/AGENTS.md` — symlinked to
  `~/.config/opencode/AGENTS.md`, `~/.codex/AGENTS.md`, `~/.config/zed/AGENTS.md`
  and `~/.gemini/GEMINI.md`. opencode injects the bodies through the `instructions`
  glob in its `opencode.json`; the others take a single file and no glob, so the
  index tells them to open the rule files themselves. Skills live at `~/.agents/skills/`, the one location Codex
  and opencode both scan, with `~/.claude/skills` a symlink to it that `make
  stow` creates. The shape, and how a third harness plugs in, is in
  [.docs-llm](../.docs-llm/global-rules-and-skills.md).
- **`settings.json` must hold no machine-specific path** — it is one file for
  every machine, and such a setting is not an error elsewhere, it is silently
  ignored. `make claude-settings-test` fails on a literal `/Users/` or `/home/`;
  use `~`. It also fails on an `autoMode` block outright: auto mode writes one
  per project and it names that checkout whether or not the line spells a path.
  Anything genuinely local (a client checkout in `additionalDirectories`, that
  block) goes in the untracked `~/.claude/settings.local.json`
  — that split is what keeps this repo safe to publish.
