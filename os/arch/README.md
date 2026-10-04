# Omarchy / Arch userland

The Hyprland side of whichever machine boots Arch — currently only the
[T480](../../devices/t480). Stowed into `$HOME` by `make stow` when
`/etc/os-release` reports `arch`.

| Path | What |
|------|------|
| `.config/hypr/` | Monitors, input, window rules |
| `.config/hyprmon/profiles/` | Saved monitor layouts for [hyprmon](https://github.com/erans/hyprmon) |

## Packages

[`install-apps.sh`](install-apps.sh) installs these, because the `Brewfile`
cannot: the monitor tool is Linux-only and the GUI app is one Homebrew ships
only as a macOS cask, and both are AUR builds, which Homebrew has no equivalent
of. `make apps` runs it right after `brew bundle`, the same `os/$ID` detection
that picks the stow package.

| App | Package | Source |
|-----|---------|--------|
| Claude Desktop | `claude-desktop` | AUR — repackages Anthropic's official `.deb`, see below |
| hyprmon | `hyprmon-bin` | AUR — monitor-manager TUI; the stowed `.config/hyprmon/profiles` are its config |

Unlike the [Kubuntu installer](../ubuntu/README.md) this adds no apt repo and
pins no key: an AUR package is built from a PKGBUILD by `makepkg`, so the trust
is in the recipe and its maintainer, not a signing fingerprint — there is
nothing fetched to pin. `yay` also runs as your user and calls `sudo` itself for
the pacman half, so the script never elevates, the opposite of the apt one. It
needs an AUR helper on `PATH` — Omarchy ships `yay` — and stops with a clear
message on a box without one. [`install-apps.test.sh`](install-apps.test.sh)
stubs `yay` and `pacman`, so it runs on any machine and `make qa` includes it.

`claude-desktop` is the AUR counterpart to the Kubuntu row — same app, a
different route to it. The Kubuntu side takes
[`aaddrick/claude-desktop-debian`](../ubuntu/README.md) for its launcher,
`--doctor` and KDE focus fix; Arch has no such wrapper to take — that project's
AUR package (`claude-desktop-appimage`) was delisted 2026-08-01 — so this is the
plainer `aur/claude-desktop`, which unpacks Anthropic's official `.deb` straight
from `downloads.claude.ai` for pacman. Closer to first-party than the Kubuntu
choice, then, but without the wrapper's Wayland and launcher extras. `yay -Syu`
keeps it current like any AUR package. If those Hyprland Wayland fixes turn out
to matter, the wrapper's AppImage is the fallback — a hand-download with no repo
behind it, so it stays out until it earns its place, the same bar the root
[README](../../README.md) sets for every other hand-download.

Everything portable — the CLI tooling shared with the Mac — is in the
[`Brewfile`](../../Brewfile) instead, installed by `make apps`.
