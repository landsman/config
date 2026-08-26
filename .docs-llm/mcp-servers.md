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

## Azure DevOps

Microsoft's own server, [`@azure-devops/mcp`](https://github.com/microsoft/azure-devops-mcp).
Auth is the Azure CLI session — `az login`, checked with `az account show` — so
again nothing secret is tracked. Two things about the entry are deliberate:

- **The organisation comes from `$AZDO_ORG`.** The slug names an employer and
  this repo is public, so it stays out of it. Put it somewhere untracked that
  the shell exports — `~/.config/bash_aliases.d/99-local.sh` is already globbed
  by both `.bashrc` and `os/macos/.zshrc`, and a file that is not in the repo
  survives `make restow` untouched:

  ```bash
  export AZDO_ORG=<slug>
  ```

  The variable is read by `sh`, not by Claude Code's `${VAR}` interpolation, and
  that is the point: unset, the guard exits before `npx` ever runs. A stdio
  server is started at every launch, and this one reaches for an Azure login as
  soon as it is up — so on a machine with no `AZDO_ORG` the unguarded version
  asks to authenticate every single time Claude Code opens. Exiting first is
  what makes the server absent rather than merely useless.

  Claude Code's own interpolation would not do: `${VAR}` with nothing set is
  passed through as the literal text — measured on 2.1.246, where the docs
  promise a missing-variable warning and no connection, and the server instead
  reports `✔ Connected` with `${AZDO_ORG}` as the organisation. An `env` block in
  `settings.json` does not feed the expansion either; only the process
  environment does.
- **`-d core repositories pipelines search`** keeps the tool surface to the four
  domains actually used; without it every domain loads.

`settings.json` still allows `mcp__azure-devops__*` from when this was
registered by hand. Plugin servers are namespaced, so those lines no longer
match — left alone here rather than guessed at, because the exact prefix is
worth reading off a live session before it is written down.

## Common commands

| Command                    | Purpose                                    |
|----------------------------|--------------------------------------------|
| `claude mcp list`          | List servers + health                      |
| `claude mcp get <name>`    | One server: scope, transport, health       |
| `claude plugin list`       | Check the plugin loaded at all             |
| `claude mcp remove <name>` | Unregister a server added with `--scope user` |
