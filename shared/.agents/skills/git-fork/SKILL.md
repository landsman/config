---
name: fork
description: Load before forking a repository, on any forge (GitHub, GitLab, Forgejo), and before cloning a fork. Carries the name every fork gets, `fork-<repo>`, and the command per forge that sets it.
trigger-keywords: fork*
---

# Forking a repository

**A fork is always named `fork-<repo>`**, never the upstream's bare name. In my
account it then cannot be mistaken for a repo of mine, it sorts together with
the other forks, and a clone of it does not shadow a checkout of the upstream.

- `<repo>` is the upstream's name as is: `owner/widget` forks to `fork-widget`.
- Never prefix twice: a repo already named `fork-*` keeps its name.
- The forge's default name is the mistake, so the name is passed explicitly,
  every time.

| Forge | Command |
|-------|---------|
| GitHub | `gh repo fork <owner>/<repo> --fork-name fork-<repo> --clone=false` |
| GitLab | `glab repo fork <namespace>/<repo> --name fork-<repo> --path fork-<repo>` |
| Forgejo (git.insuit.cz) | `fork_repo` from the `forgejo` MCP, with `name: fork-<repo>`; load the [forgejo](../git-forgejo/SKILL.md) skill first |

GitLab takes the name and the URL path separately; set both, or the URL keeps
the old name.

After forking, check the name the forge reports (`gh repo view <me>/fork-<repo>`,
`glab repo view`, `get_repo`). A forge that already has a fork of that upstream
in the account returns the existing one under its old name: say so, and rename
it rather than leave it.

## Cloning it

A fork is mine, so it goes under my owner folder, under the same name as on
the forge:

    git clone <fork url> ~/projects/landsman/fork-<repo>
    git -C ~/projects/landsman/fork-<repo> remote add upstream <upstream url>

`~/projects/github/` and `~/projects/codeberg/` are for other people's repos
cloned only to read, not for forks.
