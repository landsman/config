# Omarchy / Arch userland

The Hyprland side of whichever machine boots Arch — currently only the
[T480](../../devices/t480). Stowed into `$HOME` by `make stow` when
`/etc/os-release` reports `arch`.

| Path | What |
|------|------|
| `.config/hypr/` | Monitors, input, window rules |
| `.config/hyprmon/profiles/` | Saved monitor layouts for [hyprmon](https://github.com/erans/hyprmon) |

## Packages

These stay with the distro rather than going in the root `Brewfile`: the monitor
tool is Linux-only and an AUR build, and the GUI app is one Homebrew installs
only as a macOS cask, so Linux takes it from the AUR instead.

```
yay -S hyprmon-bin      # monitor manager TUI — the profiles above are its config
yay -S claude-desktop   # the app the Mac gets as `cask "claude"`
```

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
