# Notes for coding agents

Notes about running coding agents against this repo — read, not installed. The
files an agent actually loads live elsewhere: [AGENTS.md](../AGENTS.md) at the
root for this repo's conventions, `shared/.claude/` for what gets symlinked into
`$HOME`.

Named `.docs-llm/` rather than `.claude/` so the directory is not tied to one
vendor, and so the real `.claude/` at the root stays untracked for whatever the
tool writes there.

- [MCP Servers](mcp-servers.md)
- [Global rules and skills across harnesses](global-rules-and-skills.md) — one source, read by Claude Code and opencode
