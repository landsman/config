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

These stay with the distro rather than going in the root `Brewfile`: Hyprland is
Linux-only and both are AUR builds, which Homebrew has no equivalent of.

```
yay -S hyprmon-bin      # monitor manager TUI — the profiles above are its config
```

Everything portable — the CLI tooling shared with the Mac — is in the
[`Brewfile`](../../Brewfile) instead, installed by `make apps`.
