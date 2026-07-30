# Kubuntu userland

The KDE side of whichever machine boots Kubuntu — currently only the
[T480](../../devices/t480). Stowed into `$HOME` by `make stow` when
`/etc/os-release` reports `ubuntu`.

| Path | What |
|------|------|
| `.config/dolphinrc` | Dolphin file manager — see the KConfig caveat in the root README |
| `.config/xdg-desktop-portal/portals.conf` | Which portal backend handles file pickers and screen sharing |

## Packages

These stay with the distro rather than going in the root `Brewfile`. Homebrew on
Linux only installs a cask when that cask ships a Linux build, and almost none of
the GUI apps do — `brew install --cask 1password` fails on Linux with a
`depends_on macos` requirement, because the cask's only artifact is a macOS
`.app`. 1Password ships a `.deb` instead, from its own signed apt repo.

Add the repo once per machine:

```bash
curl -sS https://downloads.1password.com/linux/keys/1password.asc \
  | sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/amd64 stable main" \
  | sudo tee /etc/apt/sources.list.d/1password.list
```

The `.deb` is also debsig-signed, and apt refuses it without the policy in place:

```bash
sudo install -d /etc/debsig/policies/AC2D62742012EA22
curl -sS https://downloads.1password.com/linux/debian/debsig/1password.pol \
  | sudo tee /etc/debsig/policies/AC2D62742012EA22/1password.pol
sudo install -d /usr/share/debsig/keyrings/AC2D62742012EA22
curl -sS https://downloads.1password.com/linux/keys/1password.asc \
  | sudo gpg --dearmor --output /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg
```

Then install the GUI, and only the GUI:

```bash
sudo apt update && sudo apt install -y 1password
```

`AC2D62742012EA22` is the long id of the signing key (full fingerprint
`3FEF9748469ADBE15DA7CA80AC2D62742012EA22`) and has to match the `Origin id` in
the `.pol` file — if 1Password ever rotates it, all four paths above change
together. `arch=amd64` covers both Linux boxes here; the repo also publishes
`arm64`.

Not `1password-cli` — the same apt repo carries it, but the `1password-cli` cask
does ship a Linux build, so the [`Brewfile`](../../Brewfile) installs `op` on
every machine. Taking it from apt as well would put two `op` binaries on `PATH`.

Everything portable — the CLI tooling shared with the Mac — is in the
[`Brewfile`](../../Brewfile) instead, installed by `make brew`.
