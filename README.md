# Config

My localhost configuration files.

## Layout

Split on two axes — **hardware** and **OS** — because this T480 dual-boots
Kubuntu and Arch (Omarchy), and most config belongs to one or the other, not both.

| Path | Scope | Installed by |
|------|-------|--------------|
| `shared/` | Portable — any machine, any OS | `make stow` |
| `t480/` | This hardware, whichever OS is booted (Intel GPU, thinkpad_acpi) | `make stow` |
| `ubuntu/` | Kubuntu userland — KDE, Dolphin, xdg portals | `make stow` (auto) |
| `arch/` | Omarchy/Arch userland — Hyprland, hyprmon | `make stow` (auto) |
| `system/` | Root-owned files under `/` — see [system/README.md](system/README.md) | `sudo cp` (root, not stowable) |
| `.gitconfig` | Git settings, *included* into `~/.gitconfig` by absolute path | `make git` |
| `.bashrc` | Fragment appended to the distro `~/.bashrc` | `make shell` |

The OS package is picked automatically from `/etc/os-release` `ID`, so the same
`make stow` links `shared t480 ubuntu` on Kubuntu and `shared t480 arch` on Arch.
An ID with no matching directory is simply skipped.

There is no `macos/` yet — it gets created when there is actually a macOS file to
put in it, and auto-detection will pick it up once the directory exists.

`system/` is currently Ubuntu-flavoured (apt, and a pin for an Ubuntu kernel
regression). The Arch side of the same hardware tuning isn't tracked yet — add
`system-arch/` if and when it is.

## Install

```
sudo apt install stow
make stow    # symlink shared/ + t480/ into $HOME
make shell   # hook the alias loader into ~/.bashrc
make git     # hook in .gitconfig, set email + commit signing
```

For the root-owned parts, see [system/README.md](system/README.md).

### First run: existing files

`stow` refuses to overwrite real files that are already in `$HOME`. Either move
the conflicting file aside, or let stow take it over:

```
stow --no-folding --adopt -t "$HOME" shared t480
git diff        # shows what the adopted files differ in — keep or discard
```

`--adopt` moves your existing file *into the repo* and replaces it with a
symlink, so **always check `git diff` afterwards** — it can silently overwrite
the repo's version with the machine's.

## Notes

`make stow` uses `--no-folding` deliberately: without it stow symlinks whole
directories (`~/.config/hypr` → repo), and any new file an app writes there lands
inside the repo. With it, real directories are created and only the tracked files
are symlinked.

Two things are deliberately *not* stowed, because a symlink would break them:

- **`.gitconfig`** — it is included into `~/.gitconfig` rather than replacing it,
  so machine-specific values (email, signing key) stay out of the repo. A symlink
  would make `git config --global ...` write into the repo.
- **`.bashrc`** — it is a fragment, not a full shell config. Symlinking it over
  `~/.bashrc` would drop everything the distro puts there.

Aliases are split into drop-ins (`~/.config/bash_aliases.d/*.sh`) so `shared/`
and `t480/` can each contribute without both owning `~/.bash_aliases`.

**KDE config files rewrite themselves.** KConfig saves by writing a temp file and
renaming it over the target, which replaces the symlink with a regular file — so
`t480/.config/dolphinrc` will silently detach after KDE changes a setting. Run
`make restow` to re-link it (commit the drift first if you want to keep it).

## Docs

- [System config (root-owned)](system/README.md)
- [Claude](.claude/README.md)
