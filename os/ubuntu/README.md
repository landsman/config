# Kubuntu userland

The KDE side of whichever machine boots Kubuntu — currently only the
[T480](../../devices/t480). Stowed into `$HOME` by `make stow` when
`/etc/os-release` reports `ubuntu`.

| Path | What |
|------|------|
| `.config/dolphinrc` | Dolphin file manager — see the KConfig caveat in the root README |
| `.config/xdg-desktop-portal/portals.conf` | Which portal backend handles file pickers and screen sharing |

## Packages

| App | Where from |
|-----|------------|
| 1Password (GUI) | [`install-apps.sh`](install-apps.sh), from 1Password's apt repo |

`make brew` runs [`install-apps.sh`](install-apps.sh) itself, right after
`brew bundle`, so there is nothing extra to remember on a new machine — it looks
for `os/$ID/install-apps.sh` using the same `/etc/os-release` detection that
picks the stow package, and skips when there is no such file. To run it alone:

```bash
bash os/ubuntu/install-apps.sh
```

It is idempotent and asks for root only when an app is actually missing, so
re-running `make brew` on a provisioned machine neither reinstalls anything nor
prompts for a password.

These stay with the distro rather than going in the root `Brewfile` because
Homebrew on Linux installs a cask only when that cask ships a Linux build, and
almost no GUI app does. `brew install --cask 1password` fails with a
`depends_on macos` requirement: the cask's one artifact is a macOS `.app`, and
`appimage` — the stanza that would cover Linux — has nothing to point at,
because 1Password publishes only `.deb`, `.rpm` and a tarball.

The `.deb` route has one wrinkle worth knowing before reading the script:
1Password signs the repo *and* debsig-signs the package, and apt refuses to
unpack the second without a policy under `/etc/debsig/policies/` naming the key.
So the script installs a keyring, a sources list, a policy and a debsig keyring —
four paths, all derived from one pinned fingerprint, which it verifies against
the downloaded key before trusting it.

Not `1password-cli` — the same apt repo carries it, but the `1password-cli` cask
does ship a Linux build, so the [`Brewfile`](../../Brewfile) installs `op` on
every machine. Taking it from apt as well would put two `op` binaries on `PATH`.

Everything portable — the CLI tooling shared with the Mac — is in the
[`Brewfile`](../../Brewfile) instead, installed by `make brew`.
