---
paths:
  - "**/.forgejo/workflows/*.yml"
  - "**/.forgejo/workflows/*.yaml"
---

# Forgejo Actions workflows

Loaded when a Forgejo workflow file is being read or written. Forgejo Actions is
built to feel *familiar* to GitHub Actions users, and upstream is explicit that
it is **not built to be compatible** — most workflows port with small changes,
and those small changes are the whole job of a migration. What is true of Forgejo
anywhere and what is true of the homelab instance at `git.insuit.cz` are
different things; the two halves below keep them apart.

## Forgejo in general

True of any Forgejo 16 instance, this one included.

### Workflow files

Workflows live in `.forgejo/workflows/`, one YAML file per workflow. The shape
mirrors GitHub Actions: `name:`, `on:`, `jobs:`, `steps:`, the same trigger types
(`push`, `pull_request`, `schedule`, `workflow_dispatch`) and the same step keys
(`uses:`, `run:`, `with:`).

**With no `.forgejo/workflows/` directory, Forgejo runs `.github/workflows/`
instead.** So a mirrored repo already runs its GitHub workflows unchanged — and
the first file written into `.forgejo/workflows/` switches that fallback off for
every other one. Migrate the whole directory in one commit, or the workflows left
behind stop running and nothing says so.

### `uses:` does not point at github.com

A bare `uses: actions/checkout@v5` is resolved against `DEFAULT_ACTIONS_URL`
(`https://data.forgejo.org` by default), so it fetches
`https://code.forgejo.org/actions/checkout` — a different repository with its own
tags. Carrying a version across from a GitHub workflow is how a migrated file
fails to resolve.

Read the tag off the forge that will serve it, not off GitHub:

    curl -s https://code.forgejo.org/api/v1/repos/actions/checkout/releases/latest | jq -r .tag_name

To keep GitHub's copy deliberately, write the whole URL —
`uses: https://github.com/actions/checkout@v5` — so the choice is visible.

### Differences from GitHub Actions

- **`permissions:` is ignored by Forgejo 16**, and so is `continue-on-error`;
  some `github` context keys are missing too. Token scope comes from an
  Authorized Integration (user `Settings` → `Authorized Integrations`), not from
  the workflow file. Write `permissions:` for readability if you like, but do not
  rely on it for access control.
- **The default runner image is small.** A stock Forgejo runner uses Debian
  bookworm with node and little else, where GitHub ships a fat `ubuntu` image —
  `git`, `jq`, `docker` and friends are not there unless the label provides them
  or the workflow installs them. This instance pins gitea's `runner-images`; see
  the homelab half.
- **OIDC replaces `permissions: id-token: write`.** `enable-openid-connect: true`
  at workflow or job level injects `ACTIONS_ID_TOKEN_REQUEST_URL` and
  `ACTIONS_ID_TOKEN_REQUEST_TOKEN`. The ID token audience is not confidential —
  store it in a repo variable (`vars.*`), not a secret.
- **Registry push from Actions** requires an authorized-integration JWT (since
  16.0.1) in the `docker login` password field. The automatic `forgejo.token`
  **cannot push packages** (`401 Unauthorized`). See
  `~/projects/landsman/homelab/forgejo-runner/CAVEATS.md` for the full
  token-scoping story.
- **Package visibility follows the owner**, not the repository. A private repo
  with a public owner ships public packages. To ship private images, push under
  a private organization.

### Local validation

There is no `forgejo act`. The `forgejo` binary is the server — the local runner
is a separate program, `forgejo-runner exec`, and upstream ships it as a Linux
binary, so on the Mac it is the container:

    docker run --rm -v "$PWD:/w" -w /w \
      -v /var/run/docker.sock:/var/run/docker.sock \
      data.forgejo.org/forgejo/runner:13 forgejo-runner exec --list

It reads `.forgejo/workflows/` by default. Swap `--list` for `-n` to dry-run,
`-W` to pick one file, `-j` one job. What it proves is syntax, event detection
and step resolution — it runs against its own default image, not the homelab's
labels, so a green run here is not a pass there.

### Where the docs live

The upstream documentation is reachable three ways, so an agent can check a
trigger, builtin action or config key without guessing from memory:

- **Online:** https://forgejo.org/docs/latest/
- **Private mirror on this instance:** https://git.insuit.cz/tools-mirror/forgejo-docs
  (a `tools-mirror` repo, public, reachable on the homelab network even when
  codeberg.org is not)
- **Local clone:** `~/projects/codeberg/forgejo/docs/` — grep-able:

      rg -n "forgejo" ~/projects/codeberg/forgejo/docs/docs/user/actions/reference.md

Most useful pages:

- `docs/user/actions/actions.md` — which triggers fire which events
- `docs/user/actions/reference.md` — the full workflow syntax
- `docs/user/actions/github-actions.md` — compatibility and differences vs GitHub
- `docs/user/actions/security-openid-connect.md` — OIDC tokens from Actions
- `docs/user/api/authorized-integrations.md` — the JWT the registry push needs
- `docs/admin/actions/configuration.md` — runner/instance config keys

**The clone tracks `next`, the development version**, which is not what a pinned
instance runs: `git -C ~/projects/codeberg/forgejo/docs switch v16.0` before
trusting a page, and `git -C ~/projects/codeberg/forgejo/docs pull --ff-only` to
refresh either branch.

## The homelab instance (git.insuit.cz)

True only of the runner this machine's homelab runs; write workflows against
these constraints even when the syntax in the general half would allow more.

### Runner labels

The runner at `git.insuit.cz` exposes two labels:

| Label           | Execution   | Image                                                |
|-----------------|-------------|------------------------------------------------------|
| `ubuntu-latest` | Docker      | `docker.gitea.com/runner-images:ubuntu-22.04`        |
| `self-hosted`   | Host shell  | —                                                    |

`ubuntu-latest` runs the job inside a container on the runner host (Docker via the
host socket, not dind). `self-hosted` runs directly on the host shell — use it for
steps that need the host Docker daemon (e.g. `docker buildx`).

`force_pull: true` is set in the runner config, so the job image is refreshed on
every run.

### Instance-specific gotchas

- **`cache: type=gha`** is unreachable from the runner host — the Actions cache
  server is on the NAS and the runner cannot reach it. Avoid `cache-from` /
  `cache-to: type=gha`; let builds pull fresh.
- **`setup-qemu-action`** stalls on cache restore before registering binfmt.
  Register binfmt on the host once (`multiarch/qemu-user-static`) and omit the
  setup-qemu step from workflows.
- **Registry auth against this instance** follows the general rule above, but the
  token-scoping workaround here is a dedicated bot account — the full story is in
  CAVEATS.md.
- **Package visibility against this instance** matters because the homelab's
  public-account/private-repo pairing ships public images; push under a private
  organization.

### Instance details

- **URL:** `https://git.insuit.cz/`
- **Runner host:** `jesse.pollos` (x86 Debian 13)
- **Forgejo version:** 16
- **Runner version:** 13
- **Full setup and gotchas:** `~/projects/landsman/homelab/forgejo-runner/`
