---
name: commit-messages
description: Load before writing a commit message or a pull-request title — including before running `git commit`, `gh pr create`, `gh pr edit --title` or `glab mr create`. The always-loaded commit-messages rule carries the shape and the type table; this skill carries what a subject has to say, why PR titles are in scope, breaking changes, and where the convention departs from Conventional Commits and commitlint.
---

# Commit messages and PR titles

The shape and the type vocabulary are in the always-loaded
[commit-messages rule](../../rules/commit-messages.md) and are not repeated here.
One thing the rule does not say: **scope is a noun naming a part of the codebase**,
not a verb and not a ticket id.

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
title follows every rule in the rule file. This is the half that actually lands in
history, and the half a local hook cannot check — enforce it in CI on
`pull_request` with the same validator, or the main branch fills up with
`Stripe payments: local setup (#143)`.

## Breaking changes

Either mark the prefix or write the footer; the marker is `!` immediately before the
colon, and the footer is `BREAKING CHANGE:` — **uppercase**, the one case-sensitive
token in the spec.

    <type>(<scope>)!: <subject>
    be(api)!: drop the v1 checkout endpoint

## Where this sits relative to the ecosystem

Worth knowing so the rules can be defended, and so a linter's defaults are not
mistaken for the spec:

- **Conventional Commits 1.0.0** mandates the `<type>[scope][!]: <description>` shape
  and the required colon-space. It explicitly says its units **MUST NOT be treated as
  case-sensitive**, except `BREAKING CHANGE`. So "lowercase" does **not** come from
  the spec. Types beyond `feat` and `fix` are explicitly allowed, which is what makes
  our vocabulary conformant rather than a deviation.
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

Dependabot writes its own messages and reads none of this; the
`commit-message.prefix: deps` setting that aligns it lives in the
[GitHub Actions rule](../../rules/github-actions.md), which loads whenever
`.github/dependabot.yml` is open.

## Never in a commit message

No tool attribution, no `Co-Authored-By` for an assistant, no session URLs, no
"generated with" footers. See the [attribution rule](../../rules/attribution.md).
