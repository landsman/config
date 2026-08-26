# MCP Servers

Personal setup notes for MCP servers used across projects. The servers are
agent-agnostic; the commands below are Claude Code's, because that is the client
in use here. Another client reads the same server URLs from its own config.

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

## Rohlík

Docs: https://www.rohlik.cz/mcp-docs

Install (user scope):

```bash
claude mcp add-json rohlik '{"type":"http","url":"https://mcp.rohlik.cz/mcp"}' --scope user
```

Auth is OAuth against an ordinary Rohlík account and the client drives it, so
there is nothing to put in the config — no token, no header, which is what
makes the command above safe to write down here. Until the browser round trip
happens it reads:

```bash
claude mcp get rohlik
# Status: ! Needs authentication
```

Run `/mcp` in Claude Code once to get through it.

That account is the shopping account, not a sandbox: the cart these tools fill
is the one that gets delivered. Worth reading a tool's arguments before
approving it, rather than approving the server wholesale in `settings.json`.

## Common commands

| Command                    | Purpose                       |
|----------------------------|-------------------------------|
| `claude mcp list`          | List servers + health         |
| `claude mcp list-tools`    | Show tools exposed by servers |
| `claude mcp remove <name>` | Unregister server             |
