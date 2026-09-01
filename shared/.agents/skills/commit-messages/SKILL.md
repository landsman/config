---
name: commit-messages
description: Load before writing a commit message or a pull-request title. Carries the type vocabulary, the lowercase and prefix rules, what a subject line has to say, and where this convention departs from Conventional Commits and commitlint. Squash-merge turns a PR title into a commit subject, so PR titles are in scope too.
---

# Commit messages and PR titles

    <type>: <subject>
    <type>(<scope>): <subject>          # when the repo holds more than one project
    <type>(<scope>)!: <subject>         # breaking

Scope is a noun naming a part of the codebase, not a verb and not a ticket id.

## Two hard rules

**Always a type prefix.** No bare subjects. A commit with no type is a commit nobody
can filter, group, or generate a changelog from — and the prefix is what tells a
reader which drawer a change belongs in before they read a word of it.

**The subject always starts with a lowercase letter.** Including when the first word
is a class, a table, or a tool. Do not capitalise to be "correct" about an
identifier — reword so the identifier is not first:

    ✅ be(auth): let User extend SoftDeletableEntity
    ❌ be(auth): User extends SoftDeletableEntity

Mid-subject, proper nouns and identifiers keep their own casing: `deps: bump GHCR
mirror to 1.173.0`, not `ghcr`. Lowercase the *sentence*, not the names.

No full stop at the end.

## The types

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

Add a type when something genuinely does not fit, rather than forcing it — but reach
for the list first, because a per-repo vocabulary is how a convention stops being one.

## The subject says why, not what

The prefix says which drawer; it does not excuse `devops: update workflow`. The diff
already says what changed. If the subject only survives because the prefix is
carrying it, it is not written yet.

    ❌ devops: update workflow
    ✅ devops: run the PNG check on every PR, not just code ones

    ❌ be: fix bug
    ✅ be(pos): keep the slug when a till is renamed, QR codes are already printed

## PR titles are commit messages

A squash-merge writes the **PR title** as the subject on the main branch. So a PR
title follows every rule above. This is the half that actually lands in history, and
the half a local hook cannot check — enforce it in CI on `pull_request` with the same
validator, or the main branch fills up with `Stripe payments: local setup (#143)`.

## Breaking changes

Either mark the prefix or write the footer; the marker is `!` immediately before the
colon, and the footer is `BREAKING CHANGE:` — **uppercase**, the one case-sensitive
token in the spec.

    be(api)!: drop the v1 checkout endpoint

## Where this sits relative to the ecosystem

Worth knowing so the rules can be defended, and so a linter's defaults are not
mistaken for the spec:

- **Conventional Commits 1.0.0** mandates the `<type>[scope][!]: <description>` shape
  and the required colon-space. It explicitly says its units **MUST NOT be treated as
  case-sensitive**, except `BREAKING CHANGE`. So "lowercase" does **not** come from
  the spec. Types beyond `feat` and `fix` are explicitly allowed, which is what makes
  the vocabulary above conformant rather than a deviation.
- **`@commitlint/config-conventional`** is where the casing rules people quote
  actually live: `type-case: lower-case`, `subject-full-stop: never`,
  `header-max-length: 100`, and `subject-case` disallowing `sentence-case`,
  `start-case`, `pascal-case`, `upper-case`.
- **This convention is stricter than commitlint on one point.** `subject-case` checks
  the shape of the *whole* subject, so `User extends SoftDeletableEntity` passes it —
  it is not sentence-case (it has capitals later), not start-case, not pascal-case.
  Our rule is simply "first character is `[a-z]`", which a regex enforces and
  commitlint's default would let through.
- **Types differ from the Angular/commitlint default enum** (`build`, `chore`, `ci`,
  `docs`, `feat`, `fix`, `perf`, `refactor`, `revert`, `style`, `test`). Ours splits
  by *area* (`fe`/`be`) where theirs splits by *kind*. If a repo ever needs
  changelog tooling keyed to `feat`/`fix`, that is the trade to reopen — not before.

## Dependabot

It writes its own messages and does not read this. It emits `build(deps):` by
default; align a repo with `commit-message.prefix: deps` in `.github/dependabot.yml`
when touching that file anyway, rather than as a sweep of its own.

## Never in a commit message

No tool attribution, no `Co-Authored-By` for an assistant, no session URLs, no
"generated with" footers. See the attribution rule.
