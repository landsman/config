# Everything as code

**Nothing is set up by hand. A change to a machine or a service lands in a repo
first, and a plain `.sh` file counts.** Terraform, a compose file, a Makefile
target, a shell script — the form does not matter, the file does.

A command typed into a shell is not a change. It is a change that will be lost:
the next reinstall drops it, nobody can review it, and the only record that it
happened is somebody's memory. That is how a box ends up in a state nobody can
reproduce and nobody dares touch.

The test: **if this machine were rebuilt tomorrow, what brings it back?** If the
answer is "I remember doing it", it is not done.

What this covers, not only servers:

- a service published, a port opened, a proxy or tunnel pointed somewhere;
- an account, a bot, a token, a key, a permission;
- a cron job, a timer, a backup;
- a DNS record, a firewall rule, a setting toggled in a web console.

## My own machines: the config repo, nothing device-only

The same goes for the laptops themselves. **A setting that lives only on one
device is not allowed** — an agent hook, a terminal or editor setting, a shell
alias, an app preference. It goes into `~/projects/landsman/config`: the shared
config when it belongs everywhere, that host's device package when it really
differs per machine.

That includes the places that feel private and temporary: a
`settings.local.json`, a `.claude/` in someone else's repo, a file under
`~/Library`. Those are exactly where it goes missing. A Claude Code `Stop` hook
in one client repo's untracked `.claude/settings.local.json` once raised a
second notification on every turn. Nothing in the config repo explained it,
so it took a process trace to find.

So when I ask for something on a machine, the change is a commit in the config
repo that installs it, never an edit in place. When you find one already
sitting on a device, say so, and move it into the repo or delete it. Two
exceptions: a secret goes to 1Password and is referenced from the repo, and a
setting that names a client never comes here, because this repo is public (see
[where the repos live](where-repos-live.md)). It goes into that client's repo,
or, when it cannot, stays in the untracked `~/.claude/settings.local.json` —
which `make claude-settings-test` already expects.

## Doing it in the right order

Write the code, then run it — that way what ran is what is in the repo. When
something has to be fixed *now*, run the command, then put it in the repo in the
same session and say so in the same breath. Not "later": later is the state
nobody can reproduce, with a commit message that never gets written.

## When the only way in is a web UI

Some things have no API worth the trouble — a team in a forge, a token in a
cloud console, a webhook at a payment provider. Those still get a file: a script
that does the part that can be automated and **a runbook step for the rest**,
naming what was created, where its secret lives and what it is for. The code is
then the checklist, and the checklist is the record.

## Make it idempotent

A script that can be run twice without damage is also the answer to *what is set
up on this box*. One that only works on a clean machine gets run once and then
rots, because nobody dares run it again.

## What it is not

Not ceremony. A ten-line `.sh` in the repo beats a perfect Terraform module that
does not exist, and beats a beautiful plan to write one. The bar is that the
thing is written down and runnable, not that it is elegant.
