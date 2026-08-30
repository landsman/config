# Commit messages

`<type>: <subject>`, or `<type>(<scope>): <subject>` when the repo holds more
than one project. Lowercase throughout, no full stop.

    security: scan for leaked secrets in the supabase functions
    deps: bump the cloudflare provider to 6.0
    devops(pollos): watch the terraform providers, nothing tracked them
    fe: stack the footer on narrow viewports
    docs: say why the mirror is not tagged latest

The types:

| Type | For |
|------|-----|
| `security` | vulnerabilities, scanners, secrets, hardening |
| `deps` | bumping a dependency to a new version |
| `devops` | CI, build, release, infrastructure, tooling config |
| `fe` | frontend work |
| `be` | backend work |
| `docs` | documentation only |
| `chore` | housekeeping that changes no behaviour |

`deps` is the bump itself; **teaching CI to watch for bumps is `devops`.** That
distinction is the one that actually comes up.

Add a type when something genuinely does not fit, rather than forcing it — but
reach for the list first, because a per-repo vocabulary is how a convention
stops being one.

Two things this does not change:

- **The subject still says why, not what.** The prefix says which drawer the
  change belongs in; it does not excuse `devops: update workflow`. If the
  subject only survives because the prefix is carrying it, it is not written yet.
- **Lowercase the sentence, not the names.** `deps: bump GHCR mirror to 1.173.0`,
  not `ghcr`. Proper nouns, tool names and identifiers keep their own casing.

Dependabot writes its own messages and does not read this file. It emits
`build(deps):` by default; align a repo with `commit-message.prefix: deps` in
`.github/dependabot.yml` when touching that file anyway, rather than as a
sweep of its own.
