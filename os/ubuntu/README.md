# Kubuntu userland

The KDE side of whichever machine boots Kubuntu — currently only the
[T480](../../devices/t480). Stowed into `$HOME` by `make stow` when
`/etc/os-release` reports `ubuntu`.

| Path | What |
|------|------|
| `.config/dolphinrc` | Dolphin file manager — see the KConfig caveat in the root README |
| `.config/xdg-desktop-portal/portals.conf` | Which portal backend handles file pickers and screen sharing |

## Packages

[`install-apps.sh`](install-apps.sh) installs these from the vendors' own apt
repos, because the `Brewfile` cannot:

| App | Package | Repo |
|-----|---------|------|
| 1Password | `1password` | `downloads.1password.com` — also debsig-signed, see below |
| Sublime Text | `sublime-text` | `download.sublimetext.com` (flat repo) |
| DBeaver CE | `dbeaver-ce` | `dbeaver.io/debs` (flat repo) |
| Docker Engine | `docker-ce` + cli, containerd, buildx, compose | `download.docker.com` |
| Tailscale | `tailscale` | `pkgs.tailscale.com` |

Docker is the *engine*, not Docker Desktop: Desktop for Linux is a hand-download
`.deb` with no repo behind it, and the engine is what
[`lazydocker`](../../Brewfile) actually talks to. Two follow-ups are left to you
on purpose — `usermod -aG docker $USER` (root-equivalent, so it should be a
decision, not a side effect of `make apps`) and `sudo tailscale up`.

### Not installable this way

| App | Why |
|-----|-----|
| ChatGPT, Claude, Perplexity | No Linux desktop app — macOS and Windows only |
| Figma | Browser only on Linux, no desktop build |
| WhatsApp | No official Linux desktop app |
| Microsoft Teams | Discontinued. `packages.microsoft.com/repos/ms-teams` still resolves, but its `Packages` index is 0 bytes and was last built in Feb 2023 |
| iTerm2, PowerFlow | macOS-only by nature; Ghostty covers the terminal here |
| Webex, Zed, JetBrains Toolbox | Linux builds exist, but as a hand-download `.deb`, an install script and a tarball respectively — none is an apt repo, so none gets updates through apt. Worth adding only deliberately |

`make apps` runs [`install-apps.sh`](install-apps.sh) itself, right after
`brew bundle`, so there is nothing extra to remember on a new machine — it looks
for `os/$ID/install-apps.sh` using the same `/etc/os-release` detection that
picks the stow package, and skips when there is no such file. To run it alone:

```bash
bash os/ubuntu/install-apps.sh
```

It is idempotent and asks for root only when an app is actually missing, so
re-running `make apps` on a provisioned machine neither reinstalls anything nor
prompts for a password.

These stay with the distro rather than going in the root `Brewfile` because
Homebrew on Linux installs a cask only when that cask ships a Linux build, and
almost no GUI app does. `brew install --cask 1password` fails with a
`depends_on macos` requirement: the cask's one artifact is a macOS `.app`, and
`appimage` — the stanza that would cover Linux — has nothing to point at,
because 1Password publishes only `.deb`, `.rpm` and a tarball.

Every signing key is **pinned by fingerprint** and checked against the download
before it is installed. Piping `curl` straight into a keyring is what the vendor
instructions all say, but that key then authenticates root-owned packages
indefinitely, so a hijacked bucket or an intercepting proxy should fail the
install rather than quietly win it. If a vendor genuinely rotates a key the
script stops with the two fingerprints side by side; verify the new one against
the vendor's own documentation before editing the constant.

1Password needs two extra files the others do not: it signs the repo *and*
debsig-signs the package, and apt refuses to unpack the second without a policy
under `/etc/debsig/policies/` naming the key.

[`install-apps.test.sh`](install-apps.test.sh) covers all of this with `apt`,
`dpkg`, `curl` and `gpg` stubbed and every root-owned path redirected into a
temp directory, so it runs on any machine — `make qa` includes it. The case it
exists for is the mismatched fingerprint: a pin that silently passes everything
would be worse than no pin at all.

Not `1password-cli` — the same apt repo carries it, but the `1password-cli` cask
does ship a Linux build, so the [`Brewfile`](../../Brewfile) installs `op` on
every machine. Taking it from apt as well would put two `op` binaries on `PATH`.

Everything portable — the CLI tooling shared with the Mac — is in the
[`Brewfile`](../../Brewfile) instead, installed by `make apps`.
