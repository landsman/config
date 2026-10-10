# Where the repos live

Every checkout on every machine sits under `~/projects/`. That is
`/Users/landsman/projects` on macOS and `/home/landsman/projects` on Kubuntu —
`~` covers both, and nothing outside it is a repo.

The level below is the owner, not the forge, so `landsman/config` is

    ~/projects/landsman/config

A client with more than one product gets one level more. `github/` and
`codeberg/` are filed differently on purpose: they hold other people's repos,
cloned to read, sorted by forge because there is no relationship to sort them
under.

A name like `landsman/config` is therefore already most of a path. Resolve it
with `ls`; if the guess misses, `ls ~/projects` lists every owner in one screen.

## Only `~/projects/landsman/*` may be named

The rest of that folder is client and employer work, and my own repos are
public. No other owner folder, repo name, product, domain or client name goes
into anything that leaves the machine — a commit message, a PR title or body, an
issue, a code comment, a doc, a screenshot — in this repo or any other.

There is always a version that carries the same information without the name: *a
work Go repo*, *a monorepo several agents were working in*, *a client's backend*.
What makes the note worth writing is the shape of the problem, never whose it
is. If only the real path would make the point, drop the point.

This is not the same rule as pasting a secret. A repo name leaks who I work for
and what they are building, which is theirs to disclose and not mine.

### It hides in defaults and examples, not in prose

Nobody writes "our client X" in a paragraph by accident. The name gets in
through the places that feel like configuration:

    org=${ORG:-acme}                 # a default in a script
    bot=${BOT_USER:-acme-bot}        # …and the account it names
    | `acme-bot` | pushes images |   # a table of "what exists on this box"
    FORGEJO_INTERNAL_URL=https://…   # an example with a real value in it

All four are code, so they read as neutral, and all four ship the name. This
has already happened once: a helper in a public homelab repo defaulted to a
client's organisation and its bot account, and the pull request body repeated
it.

So, in any repo that is not that client's own:

- **A default, an example or a sample value is a placeholder** — `<org>`,
  `<org>-bot`, `<host>.<tailnet>.ts.net`. Prefer `${ORG:?set ORG}` over a
  default: a missing value that stops the script is better than a real one that
  ships.
- **The real values live where the work does** — `.env` on the box, the
  project's own private runbook, 1Password. A public repo says the *shape*, the
  private one says the name.
- **An inventory of what exists on a machine** — accounts, stacks, tokens —
  describes the pattern and points at the box (`forgejo admin user list`) rather
  than listing the real names.

### The list of names is in the brain

Which names those are cannot live in this repo, because this repo is public.
They are in the brain's **Names that stay private** page,
`~/projects/landsman/brain/wiki/names-that-stay-private.md`. It says what counts
as the name (the organisation on the forge, the product, its domains and
subdomains, accounts made for them on shared infrastructure) and which names are
mine and therefore fine anywhere.
The names themselves, each with its owner, are `private-names.txt` at the root
of the brain — the one list, which the hook below reads too.

**Read both before writing into a repo that is not that owner's** — the same
moment the [brain](brain.md) rule already says to look there.

**A git hook checks the diff and the commit message**:
`bin/git/forbidden-names.sh`, wired in `.gitconfig` for every repo. It reads that
same file, one `<owner> <regex>` per line, so the list never enters this repo,
and lets each owner's names through inside that owner's own repos. A name that
belongs to more than one folder — a client whose product sits under another
owner's folder — lists every one of them, comma-separated (`acme,acme-holding`).
A refused commit means reword with a placeholder, not `--no-verify`.

**The PR title and body it cannot see**, and the body is the one nothing else
checks. Run it over them before posting:

    printf '%s\n' "$TITLE" "$BODY" | ~/projects/landsman/config/bin/git/forbidden-names.sh -

If something did get out: fix the file, **fix the pull request body**, and check
`git log --grep` before deciding whether history has to be rewritten.

## Do not sweep `$HOME` with `find`

It is slow, it walks `Library/`, caches and every `node_modules`, and it answers
wrong: git worktrees live under `.claude/worktrees/` and in `/private/tmp`, so a
search matching on directory name reaches a detached copy of a repo before the
real checkout — and editing a stale worktree that looks right is worse than not
finding it at all.

It also prints every client folder in `~/projects` into the transcript, which is
what the section above is about. Read the path, do not hunt for it.
