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
