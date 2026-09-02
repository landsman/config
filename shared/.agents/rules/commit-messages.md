# Commit messages

`<type>: <subject>`, or `<type>(<scope>): <subject>` when the repo holds more
than one project. Lowercase throughout, no full stop.

**The long form lives in the `commit-messages` skill** — worked examples of a
subject that says why, enforcing PR titles in CI, breaking changes, and where
this sits relative to Conventional Commits and commitlint. Load it before
writing a commit or a PR title. What stays here is everything needed *before*
the mistake, because two of the five harnesses read this file and scan no
skills at all.

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

**A type prefix is never optional, and the subject always starts with a lowercase
letter** — including when the first word is a class, a table or a tool. Do not
capitalise to be "correct" about an identifier; reword so the identifier is not
first: `be(auth): let User extend SoftDeletableEntity`, never `be(auth): User
extends SoftDeletableEntity`.

**A squash-merge writes the PR title as the commit subject**, so a PR title
follows every rule here. That is the half that lands on the main branch and the
half a local hook cannot see.

Two things this does not change:

- **The subject still says why, not what.** The prefix says which drawer the
  change belongs in; it does not excuse `devops: update workflow`. If the
  subject only survives because the prefix is carrying it, it is not written yet.
- **Lowercase the sentence, not the names.** `deps: bump GHCR mirror to 1.173.0`,
  not `ghcr`. Proper nouns, tool names and identifiers keep their own casing.
