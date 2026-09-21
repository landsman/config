# Caveats

Background for the rules in [`../rules/`](../rules/): why a rule is worded the way it
is, what was tried and rejected, and the traps that cost an hour each. None of it is
needed to *follow* a rule, which is the whole point of it being here.

A rule is loaded unconditionally, so every line of it is paid for on every session,
whatever the session turns out to be about. A caveat is paid for once, by whoever
actually needs it. Moving the reasoning here is what lets a rule stay short without
the reasoning being lost.

| Caveats | Read when |
|---------|-----------|
| [Browser automation](browser-automation.md) | the `ai-e2e` instance misbehaves, a machine is new, or someone proposes simplifying part of the setup away |

## The conventions

- **One file per rule, named after it.** `caveats/browser-automation.md` backs
  `rules/browser-automation.md`. Add a row above at the same time.
- **Nothing auto-loads this directory.** `make stow` creates `~/.agents/caveats/` like
  any other path under `shared/`, but `agents-link` symlinks only `rules` and `skills`
  into `~/.claude`, so no harness scans this one. It is read when something points at
  it and never otherwise.
- **The rule links here by absolute path**, `~/.agents/caveats/<name>.md`, because
  `~/.claude/rules` is a symlink and a relative `../caveats/` resolves differently
  depending on which path the rule was opened through.
- **The test for where a paragraph goes:** does an agent have to know this *before*
  acting? If yes it belongs in the rule, however uncomfortable that is. If it only
  explains, justifies or warns about a past mistake, it belongs here.
