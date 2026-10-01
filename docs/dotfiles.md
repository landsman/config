# How the dotfiles are linked

Why some files are stowed, some included or sourced, and some patched — and what each choice protects.

- **`--no-folding` is deliberate** — without it stow symlinks whole directories
  (`~/.config/hypr` → repo) and every file an app writes there lands in the repo.
  With it, real directories are created and only tracked files are symlinked.
- **`.gitconfig` is not stowed** — it is included into `~/.gitconfig` instead, so
  machine-specific values (email, signing key) stay out of the repo. A symlink
  would make `git config --global ...` write here.
- **Commit signing needs the agent, not the key file** — `gpg.format = ssh` signs
  through `ssh-keygen -Y sign`, which asks ssh-agent for the private half of
  `user.signingkey` and only reads the file (and prompts) when the agent has not
  got it. So on macOS `make git` stores the passphrase in the login Keychain with
  `ssh-add --apple-use-keychain`, and `os/macos/.zshrc` loads it back with
  `--apple-load-keychain`, because every login starts with an empty agent. Drop
  either and the first commit after a reboot asks for a passphrase — usually from
  the IDE, which has nowhere to ask.
- **`.bashrc` is not stowed** — it is a fragment, so symlinking it over
  `~/.bashrc` would drop everything the distro puts there. `make shell` appends a
  `. <repo>/.bashrc` line. (It used to `cat` the fragment in, which meant later
  edits never reached the machine — delete that block once and re-run.)
- **Aliases are drop-ins** (`~/.config/bash_aliases.d/*.sh`) so `shared/` and
  `devices/t480/` can each contribute without both owning `~/.bash_aliases`.
  `os/macos/.zshrc` loads the same directory, so they are shell-agnostic.

**JetBrains vmoptions are patched, not stowed** — Toolbox rewrites that file on
every launch with per-machine values, so a symlink into the repo would push them
back into git. `make jetbrains` patches only the lines this repo owns; see
[bin/jetbrains/README.md](../bin/jetbrains/README.md).

**KDE config files rewrite themselves.** KConfig saves by writing a temp file and
renaming it over the target, which replaces the symlink with a regular file — so
`os/ubuntu/.config/dolphinrc` will silently detach after KDE changes a setting.
`make restow` re-links it, and now backs the detached file up first rather than
failing — so commit the drift *before* running it if you meant to keep it,
otherwise it is a `.bak.<timestamp>` you have to go find.
