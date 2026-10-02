# MCP Servers

Every server this config owns lives in one tracked file,
[`shared/.agents/skills/mcp-servers/.mcp.json`](../shared/.agents/skills/mcp-servers/.mcp.json).
`make stow` links it to `~/.claude/skills/mcp-servers/`, and Claude Code loads
any folder under a skills directory that holds a `.claude-plugin/plugin.json` as
a plugin — here `mcp-servers@skills-dir`, personal scope, no marketplace and no
install step. A plugin may carry a `.mcp.json`, and that is the whole mechanism:
add a server to that file, `make restow` on a machine that has not got it yet.

The servers themselves are agent-agnostic. This arrangement is Claude Code's,
because that is the client in use here; another client reads the same URLs from
its own config.

## opencode, and why the list is written twice

opencode is the second client, so the same list is also in
[`shared/.config/opencode/opencode.json`](../shared/.config/opencode/opencode.json).
Two files because the two schemas do not overlap:

|                     | Claude `.mcp.json`         | opencode `opencode.json` |
|---------------------|----------------------------|--------------------------|
| root key            | `mcpServers`               | `mcp`                    |
| stdio               | `type: "stdio"`, `command` + `args` | `type: "local"`, `command` as one argv array |
| remote              | `type: "http"`, `url`      | `type: "remote"`, `url`   |

opencode validates its config against a schema where every MCP entry is
`additionalProperties: false` and `type` is an enum, so a Claude entry pasted in
is an error, not a no-op. And a symlink does not help: one file, two readers,
two formats. So the list is written twice and
[`bin/mcp/servers.test.sh`](../bin/mcp/servers.test.sh) holds the two to each
other — same server names, same command, the `pencil` exception named in the
script. `make bin-test` runs it, so CI gates on it; a server added to one file
and not the other fails there rather than turning up as a client that quietly
does not have it, which is how forgejo came to be a Claude Code server and not
an opencode one.

**Adding a server means editing both files.** The check catches it either way
you get it wrong; it does not make the second edit unnecessary.

pencil is the one server only opencode has. Pen.app is macOS-only, so it cannot
sit in a file every machine reads, and `opencode-config-test` is what guards
its path.

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
make bin-test                                          # the two lists agree — CI runs this
opencode mcp list                                      # what opencode actually has
```

The guarded server, azure-devops, exits 0 before it connects when `AZDO_ORG`
is unset, and says so on stderr first. Neither client treats that as absent:
Claude Code lists it as `✘ Failed to connect — CONNECTION_CLOSED` (2.1.287,
2026-10-02) and names it in every session's "failed to connect" notice, opencode
as `✗ failed / MCP error -32000: Connection closed`. The guard still earns its
place — no Azure login prompt at every launch — but "failed" on a machine
without `AZDO_ORG` is expected, not broken. forgejo reads as failed on both
whenever Tailscale is off.

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
  this repo is public, so it stays out of it. `make claude` asks for it once per
  machine and writes it to `~/.config/bash_aliases.d/99-local.sh` — untracked,
  and therefore one `make restow` cannot overwrite. The guard sources that file
  itself. `.bashrc` and `os/macos/.zshrc` glob it too, but that only reaches a
  shell: a client spawns the server as a bare `sh -c` that reads no rc file,
  which is how opencode never saw the variable
  (#160). Unset, the server fails to connect, with one line on stderr saying
  why.

  The variable is read by `sh`, not by Claude Code's `${VAR}` interpolation, and
  that is the point: unset, the guard exits before `npx` ever runs. A stdio
  server is started at every launch, and this one reaches for an Azure login as
  soon as it is up — so on a machine with no `AZDO_ORG` the unguarded version
  asks to authenticate every single time Claude Code opens. Exiting first
  trades that prompt for a quiet failed connection.

  Claude Code's own interpolation would not do: `${VAR}` with nothing set is
  passed through as the literal text — measured on 2.1.246, where the docs
  promise a missing-variable warning and no connection, and the server instead
  reports `✔ Connected` with `${AZDO_ORG}` as the organisation. An `env` block in
  `settings.json` does not feed the expansion either; only the process
  environment does.
- **`-d core repositories pipelines search`** keeps the tool surface to the four
  domains actually used; without it every domain loads.

A plugin server's tools are named `mcp__plugin_<plugin>_<server>__<tool>` —
here `mcp__plugin_mcp-servers_azure-devops__…`, read off a live session's tool
list on 2026-10-02 — so that is the prefix `settings.json` allows and denies. A
rule written as `mcp__<server>__…`, the name from when a server was registered
by hand, matches nothing and fails silently: a deny on it denies nothing.

## Forgejo

Upstream: <https://git.b4mad.industries/agentic-forges/forgejo-mcp>. Issues, pull
requests, files, releases and Actions runs on `git.insuit.cz`, which is what makes
the forge reachable from a session that has no browser.

**It is a URL, not a process on this machine:**
`https://nas.dog-macaroni.ts.net/forgejo-mcp`, served from the Pi next to Forgejo
by `forgejo-mcp/` in the homelab repo. That README covers the build, the token
and the upgrade. With Tailscale off the server fails to connect, and that is the
whole cost.

It moved there so the token is not on any machine an agent runs on. As a local
stdio server it needed `FORGEJO_ACCESS_TOKEN` in the environment, which meant
exporting it into every shell, and any agent with a shell could print it. A
Keychain entry or a 0600 file would not have helped either: a process running as
the same user can read both. Now the client sends no credential, and the server
uses its own token (`--allow-operator-token-fallback`). An agent can do what
the token allows through the tools, but it can never read the token.

The trade is that reaching the endpoint is the credential. Two things keep that
to my own devices: the Pi publishes the port on loopback only, and the tailnet
ACL keeps the tagged pollos boxes off it. That matters because jesse runs
arbitrary CI jobs. Keep both in mind before exposing it any other way, a
Cloudflare tunnel included.

The name is in clear in both client files. The homelab repo, public too,
already carries it, and it resolves only inside the tailnet.

`FORGEJO_MCP_ALLOW_FILE_PATH_UPLOAD` stays off on the server. It lets
attachment tools upload files from the host, and an injected prompt publishing a
key as a release asset is the documented failure mode.

A machine set up before this still has the old wiring. `make claude` removes a
leftover `FORGEJO_ACCESS_TOKEN` from the drop-in, and `claude mcp remove forgejo
-s user` drops the user-scope entry that carried the token inline and shadows
this one.

## Common commands

| Command                    | Purpose                                    |
|----------------------------|--------------------------------------------|
| `claude mcp list`          | List servers + health                      |
| `claude mcp get <name>`    | One server: scope, transport, health       |
| `claude plugin list`       | Check the plugin loaded at all             |
| `claude mcp remove <name>` | Unregister a server added with `--scope user` |
