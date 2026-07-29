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
| `.bashrc` | Fragment *sourced* from the distro `~/.bashrc` by absolute path | `make shell` |
| `Brewfile` | Packages — one list for every machine, macOS and Linux | `make brew` |
| `bin/` | Setup that a symlink cannot express, one directory per tool, each with its own `*.test.sh` | its own `make` target |

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
make brew    # install Homebrew if missing, then the Brewfile (stow included)
make stow    # symlink shared/ + the detected device and os packages into $HOME
make shell   # hook the alias loader into ~/.bashrc
make git     # hook in .gitconfig, set email + commit signing

make macos       # macOS only: menu bar, Dock, Finder, trackpad, formats
make macos-touchid   # macOS only: authenticate sudo with Touch ID (asks for root)
make jetbrains   # set the IDE heap; then open this repo in the IDE to get the plugins
make chrome      # Chrome's non-syncing toggles — quit Chrome first
```

`make chrome` covers the handful of Chrome settings that stay on the machine
instead of following the Google account: vertical tabs and which side the side
panel opens on. Chrome rewrites `Default/Preferences` when it exits, so the
target refuses to run while it is open — everything else in that file (site
permissions, history, the window rectangle) is left untouched.

Opening this repo in a JetBrains IDE is the last step: it offers to install every
plugin in `.idea/externalDependencies.xml` in one click, and plugins are installed
per IDE rather than per project, so that one prompt covers every project on the
machine. See [bin/jetbrains/README.md](bin/jetbrains/README.md).

`make brew` comes first because `stow` is in the Brewfile. Homebrew runs on
Linux too, which is the point: one package list for every machine instead of a
Brewfile here and an apt list there. It is heavier than `apt install stow` — a
few hundred MB under `/home/linuxbrew` — so anything a distro does better stays
with the distro; guard those lines with `if OS.mac?`. The shell needs to pick up
the new `brew` before `make stow` runs: open a new terminal, or
`eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"` (macOS:
`/opt/homebrew/bin/brew`).

`make shell` is for bash only; on macOS the stowed `~/.zshrc` sources the same
`bash_aliases.d` drop-ins itself, and puts `brew shellenv` where the repo can
see it instead of leaving it in an untracked `~/.zprofile`.

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
  `~/.bashrc` would drop everything the distro puts there, so `make shell`
  appends a `. <repo>/.bashrc` line instead. It used to `cat` the fragment in,
  which meant every later edit stopped at the repo; on a machine hooked up that
  way, delete the pasted block once and re-run `make shell`.

Aliases are split into drop-ins (`~/.config/bash_aliases.d/*.sh`) so `shared/`
and `devices/t480/` can each contribute without both owning `~/.bash_aliases`.
`os/macos/.zshrc` loads the same directory, so the drop-ins are shell-agnostic
despite the name.

**macOS System Settings are written, not stowed.** macOS keeps them in `defaults`
(binary plists that `cfprefsd` rewrites on its own schedule, mixed in with window
frames and analytics stamps), so there is no file to symlink. `bin/macos/defaults.sh`
writes only the keys this repo names and leaves the rest of the machine alone.
To add one: change it in System Settings, then diff what moved —

```
defaults read > /tmp/before   # …click the thing…   defaults read > /tmp/after
diff /tmp/before /tmp/after
```

and paste the key into the script with the type `defaults read-type <domain> <key>`
reports. `./bin/macos/defaults.sh --dry-run` prints every write without doing any.

One domain is committed whole instead: `bin/macos/symbolichotkeys.plist` is the
keyboard shortcuts, 17 of the 21 system ones turned off. That is a nested dict of
numeric IDs, so it is exported as XML and `defaults import`ed — readable as a diff,
where seventeen `-dict-add` lines would not be. Re-export it with:

```
defaults export com.apple.symbolichotkeys bin/macos/symbolichotkeys.plist
plutil -convert xml1 bin/macos/symbolichotkeys.plist
```

**Touch ID for `sudo` has no GUI switch.** The Touch ID pane in System Settings
covers the login window, Apple Pay and password autofill; `sudo` is PAM only.
Since macOS 14 Apple ships `/etc/pam.d/sudo_local.template` with the line
commented out, in a file that survives OS updates — `make macos-touchid`
uncomments it, checks the result before installing it, and leaves the terminal
open so a broken `sudo` can still be undone.

It does not work inside `tmux`: a tmux pane is not attached to the session that
owns the Touch ID prompt. `pam_reattach` fixes that, and is deliberately not here
— it would put a `/opt/homebrew` object into root's authentication stack, and
Homebrew's prefix is writable by the user it would be granting root to.

**JetBrains vmoptions are patched, not stowed** — Toolbox rewrites that file on
every launch with per-machine values, so a symlink into the repo would push them
back into git. `make jetbrains` patches only the lines this repo owns; see
[bin/jetbrains/README.md](bin/jetbrains/README.md).

**KDE config files rewrite themselves.** KConfig saves by writing a temp file and
renaming it over the target, which replaces the symlink with a regular file — so
`os/ubuntu/.config/dolphinrc` will silently detach after KDE changes a setting. Run
`make restow` to re-link it (commit the drift first if you want to keep it).

## Docs

- [ThinkPad T480](devices/t480/README.md) — hardware, known issues, kernel pin
- [MacBook Pro 16" M5 Pro](devices/macbook-pro-m5-16/README.md) — hardware, what it stows
- [HP ProDesk 600 G3](devices/hp-prodesk-600-g3/README.md) — the pollos cluster, provisioned from [landsman/homelab](https://github.com/landsman/homelab/tree/main/pollos)
- [Omarchy/Arch userland](os/arch/README.md) — Hyprland config, and the AUR packages that stay out of the Brewfile
- [T480 system config (root-owned)](devices/t480/system/README.md)
- [JetBrains](bin/jetbrains/README.md) — Toolbox install, the plugin list, and why the IDE heap is patched rather than stowed
- [Claude](.claude/README.md)
