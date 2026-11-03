# MCP Servers

Every server this config owns lives in one tracked file,
[`bin/mcp/user-servers.json`](../bin/mcp/user-servers.json), and `make claude`
registers it at Claude Code's user scope (`bin/mcp/user-servers.ts install`).
That writes to `~/.claude.json`, so the tracked JSON is the record and the
script is what brings it back: it keeps a server already registered as written,
so a rerun does not drop its sign-in, and replaces one whose entry changed. Add
a server to that file, then `make claude`.

User scope because `/mcp` lists it at the top under *User MCPs*. The list used
to be a plugin (`mcp-servers@skills-dir`, a `.mcp.json` under the skills
folder), and `/mcp` files every plugin server under *Built-in MCPs*, below some
forty servers from the claude.ai plugins, so a sign-in there was as good as
hidden. Plugin servers were also namespaced, `mcp__plugin_mcp-servers_<server>__`,
so the `mcp__forgejo__*` and `mcp__azure-devops__*` lines in `settings.json`
matched nothing; at user scope they apply again.

The servers themselves are agent-agnostic. This arrangement is Claude Code's,
because that is the client in use here; another client reads the same URLs from
its own config.

## opencode, and why the list is written twice

opencode is the second client, so the same list is also in
[`shared/.config/opencode/opencode.json`](../shared/.config/opencode/opencode.json).
Two files because the two schemas do not overlap:

|                     | Claude `user-servers.json` | opencode `opencode.json` |
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
  symlink, and a reinstall resets it — which is why the servers above are
  written by a script from a tracked list, never by hand.
- **A `.mcp.json` at a repo root** does define servers, but scopes them to that
  one repo — right for a project's own tooling, wrong for a grocery shop.

## Checking it

```bash
bin/mcp/user-servers.ts plan   # keep / add / replace per server, changes nothing
claude mcp list                # one line per server, with its health
make bin-test                  # the two lists agree — CI runs this
opencode mcp list              # what opencode actually has
```

A guarded server that finds no token or no binary exits 0 before it connects,
which Claude Code shows as an absent server. opencode shows the same state as
`✗ failed / MCP error -32000: Connection closed`, so on a session without the
token both guarded servers read as broken rather than as absent — check the env
before believing either.

A server is read when the session starts, so restart after `make claude`.
Machines that had the plugin keep dangling links in `~/.agents/skills/mcp-servers/`,
which load nothing; `rm -r` it.

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

## Better Stack

Docs: <https://betterstack.com/docs/getting-started/integrations/mcp/>

OAuth against the Better Stack account, in the browser through `/mcp`, so
nothing secret is tracked. Until then the server reads `! Needs authentication`.
Which team it sees is chosen at sign-in.

It reads **and writes**: incidents can be acknowledged and resolved, monitors,
heartbeats and dashboards created. Where those are managed in Terraform — the
homelab's `pollos/infra` — something created through the server is drift the
next apply knows nothing about, so it is for reading and triage. No read-only
mode exists; a connection can be narrowed with the `X-MCP-Tools-Only` or
`X-MCP-Tools-Except` header.

A project that lists the same server in its own `.mcp.json` takes precedence
over the user-scope one of the same name; harmless, same URL.

## Cloudflare

Docs: <https://developers.cloudflare.com/agents/model-context-protocol/cloudflare/servers-for-cloudflare/>

The one server Cloudflare calls enough on its own: the whole API through
`search()` and `execute()`, plus `docs()`. Its product servers (docs,
containers, browser, DEX, CASB) are left out, since this one reaches the
same API. Registered by `make claude` (see above), then OAuth in
the browser through `/mcp`, where the permissions are picked, so nothing secret is tracked. An API token as `Authorization: Bearer`
is the headless alternative, not used here.

It reads **and writes** anything the granted permissions allow. Where a zone
is managed in Terraform, a change through the server is drift the next apply
knows nothing about, so grant read permissions and use it to look.

## Azure DevOps

Microsoft's own server, [`@azure-devops/mcp`](https://github.com/microsoft/azure-devops-mcp).
Auth is the Azure CLI session — `az login`, checked with `az account show` — so
again nothing secret is tracked. Two things about the entry are deliberate:

- **The organisation comes from `$AZDO_ORG`.** The slug names an employer and
  this repo is public, so it stays out of it. `make claude` asks for it once per
  machine and writes it to `~/.config/bash_aliases.d/99-local.sh` — a drop-in
  both `.bashrc` and `os/macos/.zshrc` already glob, untracked, and therefore
  one `make restow` cannot overwrite. It takes a new shell to reach Claude Code.
  Unset, the server is simply absent.

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

`settings.json` allows a set of `mcp__azure-devops__*` read tools by name.

## Forgejo

Upstream: <https://git.b4mad.industries/agentic-forges/forgejo-mcp>. The GitHub
and Codeberg repositories are read-only mirrors that no longer publish images —
a link to `github.com/goern/forgejo-mcp` still resolves and is still the wrong
place to install from.

Issues, pull requests, files, releases and Actions runs on `git.insuit.cz`,
which is what makes the forge reachable from a session that has no browser.

```bash
make forgejo-mcp   # build the binary into ~/go/bin
make claude        # paste the token
```

The binary is built from `tools-mirror/forgejo-mcp` on our own forge rather than
fetched from upstream, for the reason the mirror exists at all: a build should
not stop because someone else's forge is down. That costs a checkout — `go
install <mirror-path>@latest` cannot work, because `go.mod` still declares the
upstream module path and go refuses a module whose declared path is not the one
it fetched. `go install .` inside the checkout does not care.

The **token** is machine-local for the usual reason — this repo is public. The
**instance URL is not**, and sits in `user-servers.json` in clear: `git.insuit.cz` is
already all over the homelab repo, which is public too. It is the token that is
secret, not the address.

Create it at <https://git.insuit.cz/user/settings/applications>. Three scopes
cover every tool worth having:

| Scope | Buys |
|-------|------|
| `read:user` | who am I, list my repositories |
| `write:repository` | files, branches, pull requests, Actions runs |
| `write:issue` | issues, comments, labels |

Widen it when a tool actually fails, not in advance — the token is a bearer
credential sitting in a file every shell sources.

The entry is guarded like the Azure DevOps one, and on two conditions rather
than one:

```sh
b=$(command -v forgejo-mcp || echo "$HOME/go/bin/forgejo-mcp")
[ -n "$FORGEJO_ACCESS_TOKEN" ] && [ -x "$b" ] || exit 0
exec "$b" --transport stdio --url https://git.insuit.cz
```

A machine with no token, or one where `make forgejo-mcp` has not run, gets no
server instead of a failing one. `command -v` first so an Arch box that
installed `forgejo-mcp` from the AUR uses that copy; `~/go/bin` is the fallback
because it is not on `PATH` here.

Windows has no `sh` on `PATH`, so this entry cannot start there.
[`os/windows/forgejo-mcp.ps1`](../os/windows/forgejo-mcp.ps1) builds the same
tag and registers a user-scope `forgejo` that runs the `.exe` directly. Smart
App Control blocks a local build, and has no allowlist to add it to: the
[Windows README](../os/windows/README.md#forgejo-mcp) has the options.

One thing to know before allow-listing the server: `FORGEJO_MCP_ALLOW_FILE_PATH_UPLOAD`
lets attachment tools read the host filesystem and upload it. It is off by
default and should stay off — an injected prompt uploading `~/.ssh/id_ed25519`
as a public release asset is the documented failure mode, not a hypothetical.

## Adminer Desktop

My own app, <https://github.com/landsman/adminer-desktop>. It hands an agent
the database its open window is logged into, read-only, and nothing while the
window is closed. Two switches live outside this file: **Settings → AI access**
in the app, and a login as a role that can only read — the app's
[MCP doc](https://github.com/landsman/adminer-desktop/blob/main/.docs/mcp.md)
says why the login, not the read-only transaction, is the boundary.

Guarded like Forgejo, on the binary alone. `command -v` finds the `.deb`'s
`/usr/bin/adminer-desktop` on Linux, the fallback is the macOS bundle, and a
machine with neither gets no server — which is what lets it sit in the shared
list rather than beside pencil.

The app's settings tab offers `claude mcp add adminer-desktop …`. Skip it: it
writes an unguarded entry under the same name, which the next `make claude`
replaces anyway.

## Common commands

| Command                    | Purpose                                    |
|----------------------------|--------------------------------------------|
| `claude mcp list`          | List servers + health                      |
| `claude mcp get <name>`    | One server: scope, transport, health       |
| `claude mcp remove <name> -s user` | Unregister a server                |
