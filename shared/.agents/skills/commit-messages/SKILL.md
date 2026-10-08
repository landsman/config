---
name: commit-messages
description: Load before writing a commit message or a pull-request title — including before running `git commit`, `gh pr create`, `gh pr edit --title` or `glab mr create`. The always-loaded commit-messages rule carries the shape and the type table; this skill carries what a subject has to say, why PR titles are in scope, breaking changes, and where the convention departs from Conventional Commits and commitlint.
trigger-keywords: commit*, komit*, pull request, PR title, merge request, MR title
---

# Commit messages and PR titles

The shape and the type vocabulary are in the always-loaded
[commit-messages rule](../../rules/commit-messages.md) and are not repeated here.
One thing the rule does not say: **scope is a noun naming a part of the codebase**,
not a verb and not a ticket id.

## The subject says why, not what

The prefix says which drawer; it does not excuse `ci: update workflow`. The diff
already says what changed. If the subject only survives because the prefix is
carrying it, it is not written yet.

    ❌ ci: update workflow
    ✅ ci: run the PNG check on every PR, not just code ones

    ❌ be: fix bug
    ✅ be(pos): keep the slug when a till is renamed, QR codes are already printed

## PR titles — and bodies — are commit messages

A squash-merge writes the **PR title** as the subject on the main branch. So a PR
title follows every rule in the rule file. This is the half that actually lands in
history, and the half a local hook cannot check — enforce it in CI on
`pull_request` with the same validator, or the main branch fills up with
`Stripe payments: local setup (#143)`.

The **body** is the PR description, not the branch's commits — this repo is set to
`squash_merge_commit_title=PR_TITLE` and `squash_merge_commit_message=PR_BODY`
(`gh api -X PATCH repos/<owner>/<repo> -f squash_merge_commit_message=PR_BODY`).
So whatever is in the PR lands verbatim as the commit, which means the body is
held to the rule below as much as the title is. GitHub's other squash default,
`COMMIT_MESSAGES`, instead concatenates every commit on the branch — and that is
where a `* bullet` per commit, a `---------` separator and an aggregated
`Co-authored-by` come from, the last one scraped out of the individual commits'
trailers, so it survives even a clean PR body. `PR_BODY` never does any of that.
If a merged commit grows those lines, the fix is the setting, not the message.

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

## A config repo, and picking types for a new one

The type table is shared by every repo, but no repo uses all of it. What a repo
ships decides which rows it reaches for: a web app lives in `fe`/`be`, a service in
`be`/`devops`, a dotfiles repo in `setup`. Before a first commit in an unfamiliar
repo, read its `git log` for the drawers already in use, then check they match the
table, not the other way round.

`setup` exists because a dotfiles repo had filed 37 of its 150 commits under
`devops`. Most of them were app installs, system settings and agent config;
several were workflows that were really `ci`, and only a handful were the repo's
own tooling that `devops` actually means. The drawer said nothing about most of
them.

What config repos elsewhere do, which is where `setup` plus a scope comes from:

- **The component is the prefix.** Go (`net/http: handle foo when bar`,
  <https://go.dev/wiki/CommitMessage>), nixpkgs and Home Manager
  (`starship: allow running in Emacs if vterm is used`, `foo: add module`,
  <https://home-manager.dev/manual/25.11/>), and mathiasbynens/dotfiles
  (`.macos:`, `brew.sh:`). Readable, but there is no type at all, so it does not
  mix with this convention.
- **A kind as the type, the tool or machine as the scope.** folke/dot
  (`feat(nvim)`, `fix(fish)`, `chore(ansible)`) and fredrikaverpil/dotfiles
  (`feat(wily)`, a machine's hostname, beside `feat(nix)` and `feat(claude)`). In
  both, the scope carries the information and the type carries little — it is
  mostly `feat` and `fix`.
- **Angular's `build`** is "the build system or external dependencies"
  (<https://github.com/angular/angular/blob/main/contributing-docs/commit-message-guidelines.md>),
  the same drawer as our `devops`. Neither fits installing an app on a laptop.

So `setup` names the area, as `fe` and `be` do, and the scope does what the
component prefix does in Go and nixpkgs. Keep the scopes a short, stable list —
a platform or a tool — so `git log --grep '^setup(windows)'` finds everything
that touched one machine.

Dependabot writes its own messages and reads none of this; the
`commit-message.prefix: deps` setting that aligns it lives in the
[GitHub Actions rule](../../rules/github-actions.md), which loads whenever
`.github/dependabot.yml` is open.

## Never in a commit message

No tool attribution, no `Co-Authored-By` for an assistant, no session URLs, no
"generated with" footers — not in the message, not in the PR body (it becomes the
commit), and not in a single branch commit's trailers (a `COMMIT_MESSAGES` squash
aggregates them). See the [attribution rule](../../rules/attribution.md).
