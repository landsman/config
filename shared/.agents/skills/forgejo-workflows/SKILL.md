---
name: forgejo-workflows
description: Load before writing a Forgejo Actions workflow or porting one from GitHub Actions — anything touching `.forgejo/workflows/`, `forgejo-runner`, or a repo on git.insuit.cz. The rule file carries the facts; this carries the order a port goes in, and it exists because the trigger is usually the request rather than a file, which is what the rule's `paths:` scoping cannot catch.
---

# Porting a workflow to Forgejo Actions

The facts — what Forgejo ignores, how `uses:` resolves, where the docs are
cloned, the homelab runner's labels and gotchas — are in the
[Forgejo Actions rule](../../rules/forgejo-workflows.md) and are not repeated
here. **Read that file first.** It is `paths:`-scoped, so in Claude Code it has
not loaded on its own unless a `.forgejo/workflows/` file was already open, which
during a port it never is.

## The order

1. **List `.github/workflows/` before touching anything.** The whole directory is
   the unit of work, not the file that prompted the request — step 2 says why.
2. **Port every workflow in one commit.** Forgejo falls back to
   `.github/workflows/` only while `.forgejo/workflows/` does not exist, so a
   half-port stops the rest with no error anywhere.
3. **Resolve every `uses:` against the forge that will serve it**, and read the
   tag there rather than carrying GitHub's across. The rule has the API call.
4. **Drop what Forgejo ignores** rather than porting it — the rule lists it — and
   replace the runner assumptions the image no longer provides.
5. **Dry-run before pushing**: `forgejo-runner exec --list`, then `-n`. It proves
   syntax, events and step resolution, and nothing about the target runner.
6. **Only then read the homelab half of the rule**, if the target is
   `git.insuit.cz` — labels, cache, qemu, registry auth.

Keep the GitHub workflows in git history rather than deleting them in a separate
commit: the diff that removes them is the reviewable record of what moved.

A port is finished when the workflows have run on the target instance. Files that
merely exist have been known to be skipped by a fallback nobody noticed.
