# Kubuntu userland

The KDE side of whichever machine boots Kubuntu — currently only the
[T480](../../devices/t480). Stowed into `$HOME` by `make stow` when
`/etc/os-release` reports `ubuntu`.

| Path | What |
|------|------|
| `.config/dolphinrc` | Dolphin file manager — see the KConfig caveat in the root README |
| `.config/xdg-desktop-portal/portals.conf` | Which portal backend handles file pickers and screen sharing |

## Packages

[`install-apps.sh`](install-apps.sh) installs these, because the `Brewfile`
cannot — from the vendors' own apt repos, except where the table says otherwise:

| App | Package | Repo |
|-----|---------|------|
| 1Password | `1password` | `downloads.1password.com` — also debsig-signed, see below |
| Sublime Text | `sublime-text` | `download.sublimetext.com` (flat repo) |
| DBeaver CE | `dbeaver-ce` | `dbeaver.io/debs` (flat repo) |
| Docker Engine | `docker-ce` + cli, containerd, buildx, compose | `download.docker.com` |
| Tailscale | `tailscale` | `pkgs.tailscale.com` |
| Google Chrome | `google-chrome-stable` | `dl.google.com/linux/chrome/deb` |
| Stripe CLI | `stripe` | `packages.stripe.dev` — one `stable` suite, not a codename |
| Discord | `discord` | **none** — the vendor `.deb`, see below |
| VLC | `vlc` | **none needed** — in the Ubuntu archive |
| LibreOffice | `libreoffice` | **none needed** — in the Ubuntu archive |

Docker is the *engine*, not Docker Desktop: Desktop for Linux is a hand-download
`.deb` with no repo behind it, and the engine is what
[`lazydocker`](../../Brewfile) actually talks to. Two follow-ups are left to you
on purpose — `usermod -aG docker $USER` (root-equivalent, so it should be a
decision, not a side effect of `make apps`) and `sudo tailscale up`.

The last two rows are the plain case and are here for a reason: both are in the
Ubuntu archive, so neither needs a repo, a key or a pin, and adding any of that
would be machinery bought for nothing. They are in the list only so that one
`make apps` leaves a machine with the apps [the macOS file
associations](../../bin/macos/file-associations.conf) point at — VLC for `.mp4`
and `.m4a`, LibreOffice for `.doc`, `.docx` and `.xlsx`, Chrome for links.

Discord is the one entry with no repo behind it, and it is here deliberately
rather than by oversight. It publishes a `.deb` and nothing else: no apt repo,
no checksum, no detached signature — every candidate URL beside the download
answers 403, which is what that CDN returns for an object that does not exist —
and `discord.com/api/download` redirects to whatever the current version
happens to be, so there would be nothing stable to pin even if a digest were
published. TLS is the only thing vouching for it, which is a genuinely weaker
guarantee than every other row in that table gets. Two consequences worth
knowing: apt will never update it, so `sudo apt-get remove discord` and another
`make apps` is the upgrade path (an outdated client refusing to connect is the
usual prompt), and this exception is per app, not a new rule — the hand-download
apps below stay out.

### Not installable this way

| App | Why |
|-----|-----|
| ChatGPT, Claude, Perplexity | No Linux desktop app — macOS and Windows only |
| Figma | Browser only on Linux, no desktop build |
| WhatsApp | No official Linux desktop app |
| Microsoft Teams | Discontinued. `packages.microsoft.com/repos/ms-teams` still resolves, but its `Packages` index is 0 bytes and was last built in Feb 2023 |
| iTerm2, PowerFlow | macOS-only by nature; Ghostty covers the terminal here |
| ZoomIt | Sysinternals ships it for Windows and macOS only, no Linux build |
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

The Stripe CLI is the one row here that is not a GUI app, and it is here for the
same reason the rest are: `stripe/stripe-cli`'s formula is `depends_on :macos`,
so Homebrew on Linux will not install it however portable the binary is. Its
repo publishes a single `stable` suite for every release rather than one per
codename, which is why that case ignores `$CODENAME` — the test asserts it, so
that a later sweep pasting the codename in everywhere gets caught.

Everything portable — the CLI tooling shared with the Mac — is in the
[`Brewfile`](../../Brewfile) instead, installed by `make apps`.
