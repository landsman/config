---
paths:
  - "**/.forgejo/workflows/*.yml"
  - "**/.forgejo/workflows/*.yaml"
---

# Forgejo Actions workflows

Loaded when a Forgejo workflow file is being read or written. Forgejo Actions is
a reimplementation of GitHub Actions — the syntax is largely compatible, but
what is true of Forgejo anywhere and what is true of the homelab instance at
`git.insuit.cz` are different things. The two halves below keep them apart.

## Forgejo in general

True of any Forgejo 16 instance, this one included.

### Workflow files

Workflows live in `.forgejo/workflows/`, one YAML file per workflow. The structure
mirrors GitHub Actions: `name:`, `on:` (trigger), `jobs:`, `steps:`. Forgejo
recognises the same trigger types (`push`, `pull_request`, `schedule`, `workflow_dispatch`,
etc.) and the same step types (`uses:`, `run:`, `with:`).

### Differences from GitHub Actions

- **`permissions:` is ignored by Forgejo 16.** Token scope is controlled through
  the Forgejo UI (Settings → Actions → Runners → Authorized Integrations), not
  the workflow file. Write `permissions:` for readability if you like, but do not
  rely on it for access control.
- **`ACTIONS_RUNTIME_TOKEN` / `ACTIONS_ID_TOKEN_REQUEST_URL`** are available when
  `enable-openid-connect: true` is set in the workflow. The ID token audience is
  not confidential — store it in a repo variable (`vars.*`), not a secret.
- **Registry push from Actions** requires an authorized-integration JWT (since
  16.0.1) in the `docker login` password field. The automatic `forgejo.token`
  **cannot push packages** (`401 Unauthorized`). See
  [CAVEATS.md](../../projects/landsman/homelab/forgejo-runner/CAVEATS.md) for the
  full token-scoping story.
- **Package visibility follows the owner**, not the repository. A private repo
  with a public owner ships public packages. To ship private images, push under
  a private organization.

### Local validation

`forgejo act` runs workflows locally (same concept as `nektos/act` for GitHub).
Install it alongside the Forgejo CLI:

    brew install forgejo

Then from the repo root:

    forgejo act --list          # list detected workflows
    forgejo act -n <workflow>   # dry-run a specific workflow

It picks up `.forgejo/workflows/` automatically. Use it to validate syntax and
step resolution before pushing.

### Local docs mirror

The upstream documentation is checked out at `~/projects/codeberg/forgejo-docs/`
on the `v16.0` branch, matching this instance's version. It is grep-able — reach
for it before inventing a trigger, builtin action or config key:

    rg -n "gitea" ~/projects/codeberg/forgejo-docs/docs/user/actions/reference.md

Most useful pages:

- `docs/user/actions/actions.md` — which triggers fire which events
- `docs/user/actions/reference.md` — the full workflow syntax
- `docs/user/actions/github-actions.md` — compatibility and differences vs GitHub
- `docs/user/actions/security-openid-connect.md` — OIDC tokens from Actions
- `docs/admin/actions/configuration.md` — runner/instance config keys

Refresh with `git -C ~/projects/codeberg/forgejo-docs pull --ff-only`. If the
instance later runs a different major, check out that branch instead.

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