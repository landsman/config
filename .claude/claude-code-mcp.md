# Claude Code — MCP Servers

Personal setup notes for MCP servers used across projects.

Config file: `~/.claude.json` (user scope via `--scope user`).

## Vaadin

Docs: https://vaadin.com/docs/latest/building-apps/mcp/supported-tools/claude-code

Correct URL is `https://mcp.vaadin.com/docs` (NOT `/mcp` — that path fails to connect).

Install (user scope):

```bash
claude mcp add-json vaadin '{"type":"http","url":"https://mcp.vaadin.com/docs"}' --scope user
```

Verify:

```bash
claude mcp list | grep vaadin
# vaadin: https://mcp.vaadin.com/docs (HTTP) - ✓ Connected
```

Remove:

```bash
claude mcp remove vaadin
```

## Common commands

| Command                    | Purpose                       |
|----------------------------|-------------------------------|
| `claude mcp list`          | List servers + health         |
| `claude mcp list-tools`    | Show tools exposed by servers |
| `claude mcp remove <name>` | Unregister server             |
