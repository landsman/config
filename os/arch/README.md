# Omarchy / Arch userland

The Hyprland side of whichever machine boots Arch — currently only the
[T480](../../devices/t480). Stowed into `$HOME` by `make stow` when
`/etc/os-release` reports `arch`.

| Path | What |
|------|------|
| `.config/hypr/` | Monitors, input, window rules |
| `.config/hyprmon/profiles/` | Saved monitor layouts for [hyprmon](https://github.com/erans/hyprmon) |
| `.config/omarchy/plugins/landsman.power/` | The power panel, patched to count both T480 batteries — temporary, see below |
| `install-plugins.sh` | Every shell plugin this install runs, as a list `make plugins` runs — not stowed |
| `patches/kb.system-pulse.patch` | Separators and GB in the System Pulse bar widget — applied by that script, not stowed |

## Shell plugins: `make plugins`

Which plugins are in the bar, and how each got there, is
[`install-plugins.sh`](install-plugins.sh) — a list at the bottom, one line per
step: add from git pinned to a commit, apply its patch from `patches/`, enable
with a placement, set a widget setting. Run it after `make stow`, since
`landsman.power` is stowed files. Re-running is safe; it does only what is
missing and restarts the shell only when something changed.

Adding a plugin is a line in that list, not a step in this README. Updating one
is bumping its commit there and re-running — not `omarchy plugin update`, which
would move it off the commit its patch was made against.

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
the bar entry in `~/.config/omarchy/shell.json` back to `omarchy.power`, and drop
its two lines from `install-plugins.sh`. On a fresh install, stowing the files is
not enough — `make plugins` points the bar at `landsman.power`.

## System Pulse: separators and GB, patched

[System Pulse](https://github.com/KabirBhattarai/omarchy-system-pulse) shows
CPU, memory and temperature in the bar, refreshing every 2 s. Upstream joins the
label with a hard-coded space and writes memory as `10.4G`; the patch adds a
`separator` setting (default a space, so unset it looks as upstream) and spells
memory as GB — the bar reads `17% · 10.1GB · 47°`.

The plugin is a git clone that `omarchy plugin add` owns, so the patch is kept
here and applied on top rather than stowed over it — by `make plugins`, which
also sets `"separator": " · "` on the widget and restarts the shell, because a
plugin reload alone kept the old label. Made against `d12eb18`, the commit the
list pins.

## Packages

These stay with the distro rather than going in the root `Brewfile`: Hyprland is
Linux-only and both are AUR builds, which Homebrew has no equivalent of.

```
yay -S hyprmon-bin      # monitor manager TUI — the profiles above are its config
```

Everything portable — the CLI tooling shared with the Mac — is in the
[`Brewfile`](../../Brewfile) instead, installed by `make apps`.
