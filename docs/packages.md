# How stow picks the packages

How `make stow` decides which `devices/` and `os/` packages a machine gets, and what a device package may hold.

The repo splits on two axes — **device** and **OS** — because the same laptop
multi-boots Kubuntu and Arch (Omarchy), and the same OS runs on more than one
machine. `shared/` is everything else. A file lives wherever it stays true.

Not everything is stowed:

| What | Installed by |
|------|--------------|
| `.gitconfig` | `make git` — *included* into `~/.gitconfig`, see [dotfiles.md](dotfiles.md) |
| `.bashrc` | `make shell` — *sourced* from the distro's `~/.bashrc` |
| `devices/<name>/system/` | `sudo cp` — root-owned files under `/` |
| `os/windows/` | `bootstrap.ps1` — Windows never runs `make stow` |
| `bin/` | its own `make` target — setup a symlink cannot express |

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
