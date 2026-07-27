# Omarchy / Arch userland

The Hyprland side of whichever machine boots Arch — currently only the
[T480](../../devices/t480). Stowed into `$HOME` by `make stow` when
`/etc/os-release` reports `arch`.

| Path | What |
|------|------|
| `.config/hypr/` | Monitors, input, window rules |
| `.config/hyprmon/profiles/` | Saved monitor layouts for [hyprmon](https://github.com/erans/hyprmon) |

## Packages

These stay with the distro rather than going in the root `Brewfile`: Hyprland is
Linux-only and both are AUR builds, which Homebrew has no equivalent of.

```
yay -S hyprmon-bin      # monitor manager TUI — the profiles above are its config
```

Everything portable — the CLI tooling shared with the Mac — is in the
[`Brewfile`](../../Brewfile) instead, installed by `make brew`.
