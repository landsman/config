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
    ci(pollos): watch the terraform providers, nothing tracked them
    fe: stack the footer on narrow viewports
    docs: say why the mirror is not tagged latest
    setup(windows): turn Smart App Control off, so a local build can run

The types:

| Type | For |
|------|-----|
| `security` | vulnerabilities, scanners, secrets, hardening |
| `deps` | bumping a dependency to a new version |
| `ci` | the pipeline itself — workflows, runners, the checks a push triggers |
| `devops` | build, release, infrastructure, a project's tooling config |
| `setup` | a machine in a config repo — an app installed, a system setting, an agent's config |
| `fe` | frontend work |
| `be` | backend work |
| `docs` | documentation only |
| `chore` | housekeeping that changes no behaviour |

`deps` is the bump itself; **teaching CI to watch for bumps is `ci`.** That
distinction is the one that actually comes up.

`ci` and `devops` are the pair that needs saying out loud, because they used to be
one drawer. `ci` is what the forge runs — a workflow file, a runner label, a job
that has to go green before a merge. `devops` is everything else in that
territory: a Makefile target, a Dockerfile, a compose file, the pinned toolchain.
The test is where it executes. Teaching the pipeline to build the image is `ci`;
changing how the image is built is `devops`.

`devops` and `setup` are the other pair. `devops` is about how a project is
built and shipped; `setup` is about a computer, and it only occurs in a repo whose
product *is* a machine's configuration — dotfiles, a Brewfile, an installer
script. Installing Telegram is not infrastructure, and filing it under `devops`
turns the busiest drawer into "everything that is not docs". The test is what
changes: a Makefile target that changes the machine is `setup`, one that checks
or builds the repo is `devops`. An agent's settings, hooks or MCP config are
`setup(agents)`; the prose an agent reads, a rule or a skill, is `docs`.

In such a repo the scope says where: a tool (`agents`, `git`, `brew`) or a
platform (`macos`, `windows`, `ubuntu`), the tool when both fit, and none when it
lands everywhere.

    setup: install glab, the GitLab CLI, on every platform
    setup(agents): show the brain index at every session start

Add a type when something genuinely does not fit, rather than forcing it — but
reach for the list first, because a per-repo vocabulary is how a convention
stops being one.

**A type prefix is never optional, and the subject always starts with a lowercase
letter** — including when the first word is a class, a table or a tool. Do not
capitalise to be "correct" about an identifier; reword so the identifier is not
first: `be(auth): let User extend SoftDeletableEntity`, never `be(auth): User
extends SoftDeletableEntity`.

**A squash-merge writes the PR title as the commit subject and the PR body as the
commit body**, so both follow every rule here. That is the half that lands on the
main branch and the half a local hook cannot see. The skill names the repo setting
that makes this true, and what the wrong one leaks into history.

Two things this does not change:

- **The subject still says why, not what.** The prefix says which drawer the
  change belongs in; it does not excuse `ci: update workflow`. If the
  subject only survives because the prefix is carrying it, it is not written yet.
- **Lowercase the sentence, not the names.** `deps: bump GHCR mirror to 1.173.0`,
  not `ghcr`. Proper nouns, tool names and identifiers keep their own casing.

**No email address in a subject or a PR title**, mine included. Say whose it
is ("the work address"), not what it is. The value belongs in the diff or in
a gitignored `.env`. `bin/git/forbidden-names.sh` refuses the subject at
commit time, and refuses the title when the PR is piped through it.
