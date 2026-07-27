# Config

My localhost configuration files.

## Layout

Split on two axes — **device** and **OS** — because the same laptop multi-boots
Kubuntu and Arch (Omarchy), and the same OS runs on more than one machine. A file
lives wherever it stays true.

| Path | Scope | Installed by |
|------|-------|--------------|
| `shared/` | Portable — any machine, any OS | `make stow` |
| `devices/t480/` | This hardware, whichever OS is booted (Intel GPU, thinkpad_acpi) | `make stow` (auto) |
| `devices/macbook-pro-m5-16/` | The MacBook — nothing stowed yet, macOS-only machine | `make stow` (auto) |
| `os/ubuntu/` | Kubuntu userland — KDE, Dolphin, xdg portals | `make stow` (auto) |
| `os/arch/` | Omarchy/Arch userland — Hyprland, hyprmon | `make stow` (auto) |
| `os/macos/` | macOS userland — `~/.zshrc`: PATH, mise, completion | `make stow` (auto) |
| `devices/t480/system/` | Root-owned files under `/` for that machine — see [its README](devices/t480/system/README.md) | `sudo cp` (root, not stowable) |
| `.gitconfig` | Git settings, *included* into `~/.gitconfig` by absolute path | `make git` |
| `.bashrc` | Fragment appended to the distro `~/.bashrc` | `make shell` |

Both packages are detected, so one `make stow` is correct everywhere:

- **device** from DMI `product_version` — `ThinkPad T480` → `t480`
- **os** from `/etc/os-release` `ID` — `ubuntu` / `arch`
- **macOS** has neither file, so it is detected from `hw.model` — `Mac17,8` →
  `macbook-pro-m5-16`, `macos`. That mapping is one `sed` line in the Makefile;
  a second Mac gets a second line.

A name with no matching directory is skipped with a note rather than failing, so
a new machine works before its package exists. Override when the guess is wrong:

```
make stow DEVICE=x1 OS=arch
```

Adding a device or an OS is just `mkdir devices/<name>` or `mkdir os/<name>` —
detection picks it up once the directory is there (on macOS, plus one `sed`
expression in the Makefile to map its `hw.model`).

A device package holds two kinds of thing: the dotfile trees that get symlinked
into `$HOME`, and anything that does not belong there — `docs/`, and the
root-owned `system/` tree installed with `sudo cp`. The latter must be listed in
that package's `.stow-local-ignore`, or stow will link it into the home
directory. `devices/t480/system/` is currently Ubuntu-flavoured (apt, plus a pin
for an Ubuntu kernel regression); the Arch side of the same hardware tuning isn't
tracked.

## Install

```
sudo apt install stow    # macOS: brew install stow
make stow    # symlink shared/ + the detected device and os packages into $HOME
make shell   # hook the alias loader into ~/.bashrc
make git     # hook in .gitconfig, set email + commit signing
```

`make shell` is for bash only; on macOS the stowed `~/.zshrc` sources the same
`bash_aliases.d` drop-ins itself.

For the root-owned parts, see [devices/t480/system/README.md](devices/t480/system/README.md).

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
and `devices/t480/` can each contribute without both owning `~/.bash_aliases`.
`os/macos/.zshrc` loads the same directory, so the drop-ins are shell-agnostic
despite the name.

**KDE config files rewrite themselves.** KConfig saves by writing a temp file and
renaming it over the target, which replaces the symlink with a regular file — so
`os/ubuntu/.config/dolphinrc` will silently detach after KDE changes a setting. Run
`make restow` to re-link it (commit the drift first if you want to keep it).

## Docs

- [ThinkPad T480](devices/t480/README.md) — hardware, known issues, kernel pin
- [MacBook Pro 16" M5 Pro](devices/macbook-pro-m5-16/README.md) — hardware, what it stows
- [HP ProDesk 600 G3](devices/hp-prodesk-600-g3/README.md) — the pollos cluster, provisioned from [landsman/homelab](https://github.com/landsman/homelab/tree/main/pollos)
- [T480 system config (root-owned)](devices/t480/system/README.md)
- [Claude](.claude/README.md)
