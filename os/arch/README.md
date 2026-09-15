# Omarchy / Arch userland

The Hyprland side of whichever machine boots Arch — currently only the
[T480](../../devices/t480). Stowed into `$HOME` by `make stow` when
`/etc/os-release` reports `arch`.

| Path | What |
|------|------|
| `.config/hypr/` | Monitors, input, window rules |
| `.config/hyprmon/profiles/` | Saved monitor layouts for [hyprmon](https://github.com/erans/hyprmon) |
| `.config/omarchy/plugins/landsman.power/` | The power panel, patched to count both T480 batteries — temporary, see below |

## Power panel: both batteries, cherry-picked

The packaged `omarchy-battery-status` reads only the first battery UPower lists,
so on the T480 the power panel shows the internal 22 Wh BAT0 — 100 %, 0 W — while
the external BAT1 charges. The bar icon is right; only the panel is wrong.

The fix is [omacom/omarchy#6845](https://github.com/omacom/omarchy/pull/6845),
still open. Its script is cherry-picked at `cbe0705` into a clone of the power
plugin (`omarchy plugin clone omarchy.power`), and one line of `Panel.qml` runs
that copy instead of the one on `PATH` — which cannot be shadowed, the shell puts
`/usr/share/omarchy/bin` first. Verified on Omarchy 4.0.3: 79 Wh, cycles 42 / 79.

The clone is a fork of the whole widget, so upstream changes to the panel stop
arriving while it is in use. **Once #6845 ships, delete this directory** and set
the bar entry in `~/.config/omarchy/shell.json` back to `omarchy.power`. On a fresh
install the reverse applies: stowing the files is not enough, the bar has to be
pointed at `landsman.power`, then `omarchy restart shell`.

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
