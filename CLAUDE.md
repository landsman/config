# Working in this repo

## An app goes on every platform that can run it

Adding an app is not done when it installs on the Mac. The machines multi-boot,
so a one-platform entry is a gap someone finds later on the wrong laptop.

- **Portable CLI tooling** — one `brew` line in the [Brewfile](Brewfile), no
  guard. Homebrew runs on both.
- **A cask with a Linux build** — outside the `if OS.mac?` guard, same as
  `1password-cli` and `localsend`.
- **A macOS-only cask** — inside the guard, *and* the Linux half in
  [`os/ubuntu/install-apps.sh`](os/ubuntu/README.md): the vendor's apt repo with
  its key pinned by fingerprint, a row in that README's package table, and a
  case in `install-apps.test.sh`.
- **Only a hand-download** — a `.deb` with no repo, no checksum, nothing to pin
  — is still worth installing when the app is one in daily use. It goes in the
  same script, fetched straight from the vendor, but as a *stated* exception:
  what is missing, what is left vouching for it, and how it gets updated, spelled
  out in the README beside it. Discord is the precedent. The exception is per
  app — the others in the same shape stay out.
- **No Linux build at all** — then it belongs in that README's *Not installable
  this way* table, with the reason. An unrecorded gap reads as an oversight; a
  recorded one is a decision.

Work out which of the five applies before asking. Ask when the answer would
introduce machinery the repo does not already have — a first flatpak, a first
snap, a first curl-a-tarball installer — because that is a bigger decision than
the app itself.

## GitHub Actions versions

Reference actions by their stable major tag — `actions/checkout@v7`, not a
commit SHA. The major tag is the version I read, compare and bump; a SHA tells
me nothing at a glance and turns a version bump into a lookup.

Use the **latest** major, and check what that is before writing it. Same for
every action, GitHub's own or a third party's. A model's idea of the current
version is whatever was true when it was trained: `actions/checkout` was written
here as `@v4` while v7 was out, and the repo next door still says `@v5`. Look it
up, do not recall it:

    gh api repos/<owner>/<action>/releases/latest --jq .tag_name

This holds even when a scanner asks for the SHA. `make security` excludes that
rule by id for exactly this reason. If a tool disagrees with something written
down here, change the tool's configuration, not the workflow — and say so.

## Pull requests

When the work is done and pushed, open the pull request. Do not ask first —
this is standing permission for this repo, so that the last step of a change
is not a round trip to hear "yes".

Opening only. Merging stays a decision I make, and so does anything that
touches a branch other than the one being worked on.
