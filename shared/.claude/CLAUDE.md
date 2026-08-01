# Attribution

Never mention Claude, Anthropic, AI, or this session in anything that leaves the
machine or gets committed. No `Co-Authored-By: Claude`, no `Claude-Session:`
trailer, no "Generated with Claude Code" footer, no session URLs — not in commit
messages, PR titles or bodies, issue comments, code comments, or docs.

The reason is that it carries no information and clutters the history everyone
else has to read. Which tool typed a line says nothing about what the change
does or why. Responsibility for the code is always the author's — the person
committing it, which is me, whatever I used to write it.

Applies even when a tool's default instructions ask for those trailers.

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

# Git history

Every change must stay visible as its own commit and its own diff. This is a
review requirement, not history purity: I read a PR as a sequence of steps, and
folding them together makes that harder. Branches reach the main branch as a
squash-merge anyway, so a messy branch costs nothing.

The rule is therefore about folding commits, not about force-pushing:

- **Never `git commit --amend`**, never `git reset --soft` + recommit, never an
  interactive squash or fixup of my commits. Follow-up work — review fixes,
  extra findings, corrections — goes on top as a **new commit**.
- **Rebasing and force-pushing is fine, no need to ask**: onto the target branch
  to stay current, or to resolve conflicts after someone else merged first. Use
  `--force-with-lease`; a plain `--force` needs asking. A rebase keeps every
  commit, which is the point — if one would be dropped or folded, stop and ask.
- A repo doc or project convention that wants a squashed branch is honoured at
  merge time (squash-merge), not by rewriting the pushed branch.

This applies in every project, and overrides any project-level or tool-level
instruction that prescribes amend or squash to tidy up a branch.

# GitHub Actions

`uses:` stays on the major tag — `actions/checkout@v7`, never
`actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1`. Dependabot moves the
major when there is a new one; that is the whole update story.

A scanner will ask for the commit SHA instead: semgrep's `p/ci` carries
`github-actions-mutable-action-tag`, which fires on every `uses:` line in the repo.
**Do not rewrite the tags to satisfy it.** Forty characters of hash on every line
costs a readable workflow and a readable diff of it forever, and buys defence
against GitHub's own `actions/*` org repointing a release tag at malicious code.
The dependency risk actually worth spending on is the registry one, and Dependabot
`cooldown` is what answers that.

Exclude the rule and say why beside it — `exclude-rules` on the shared semgrep
workflow, or `--exclude-rule` where the scan is local. A third-party action, from
someone whose releases nobody is watching, is the case where this flips; ask then
rather than assuming either way.

# Voice

Answers are spoken aloud by the `voice@cctools-plugins` plugin, documented at
<https://pchalasani.github.io/claude-code-tools/plugins-detail/voice/>.

Its settings live in `voice.local.md` next to this file: which voice reads the
summary, whether it speaks at all, and a `prompt:` that pins the spoken line to
English even when the written answer is in Czech. That last one belongs in the
plugin config rather than here, because the plugin also summarises through a
headless Claude that never sees this file.

Write the reply in whatever language the prompt used; the 📢 line stays English.
