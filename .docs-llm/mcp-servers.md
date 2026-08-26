# MCP Servers

Every server this config owns lives in one tracked file,
[`shared/.claude/skills/mcp-servers/.mcp.json`](../shared/.claude/skills/mcp-servers/.mcp.json).
`make stow` links it to `~/.claude/skills/mcp-servers/`, and Claude Code loads
any folder under a skills directory that holds a `.claude-plugin/plugin.json` as
a plugin — here `mcp-servers@skills-dir`, personal scope, no marketplace and no
install step. A plugin may carry a `.mcp.json`, and that is the whole mechanism:
add a server to that file, `make restow` on a machine that has not got it yet.

The servers themselves are agent-agnostic. This arrangement is Claude Code's,
because that is the client in use here; another client reads the same URLs from
its own config.

## Why not the two places you would look first

- **`settings.json` cannot define a server.** It has the policy keys
  (`allowedMcpServers`, `deniedMcpServers`, `enabledMcpjsonServers`), and its
  `mcpServers` block only sets `toolPolicy` on a server defined elsewhere. A
  hand-written definition there is not an error, it is ignored — which is the
  worst shape a config mistake can take. [Asked for upstream in March 2026, still
  open](https://github.com/anthropics/claude-code/issues/32145).
- **`~/.claude.json`** is where `claude mcp add --scope user` writes, and it is
  runtime state: sessions, OAuth tokens, per-project trust decisions. Nothing to
  symlink, and a reinstall resets it.
- **A `.mcp.json` at a repo root** does define servers, but scopes them to that
  one repo — right for a project's own tooling, wrong for a grocery shop.

## Checking it

```bash
claude plugin list | grep -A4 mcp-servers@skills-dir   # Status: ✔ loaded
claude mcp list | grep plugin:mcp-servers              # one line per server
```

Servers are namespaced by the plugin, so the name to allow-list, remove or debug
is `plugin:mcp-servers:<server>`, not `<server>`. A server still registered the
old way shadows its tracked twin — `claude mcp remove <name> -s user` drops it.

`.mcp.json` is read when the session starts, so `/reload-plugins` or a restart
after editing it.

## Rohlík

Docs: <https://www.rohlik.cz/mcp-docs>

OAuth against an ordinary Rohlík account, driven by the client, so nothing
secret belongs in the repo — no token, no header. Until the browser round trip
happens the server reads `! Needs authentication`; `/mcp` does it, once per
machine.

That account is the shopping account, not a sandbox: the cart these tools fill
is the one that gets delivered. Worth reading a tool's arguments before
approving it, rather than allow-listing the server wholesale in `settings.json`.

## Vaadin

Docs: <https://vaadin.com/docs/latest/building-apps/mcp/supported-tools/claude-code>

The URL is `https://mcp.vaadin.com/docs`, **not** `/mcp` — that path fails to
connect. No auth.

## Common commands

| Command                    | Purpose                                    |
|----------------------------|--------------------------------------------|
| `claude mcp list`          | List servers + health                      |
| `claude mcp get <name>`    | One server: scope, transport, health       |
| `claude plugin list`       | Check the plugin loaded at all             |
| `claude mcp remove <name>` | Unregister a server added with `--scope user` |
