# Install

```
make apps    # Homebrew if missing, then the Brewfile (stow included), then
             # on Linux whatever the distro has to install itself
make stow    # symlink shared/ + the detected device and os packages into $HOME
make shell   # hook the alias loader into ~/.bashrc
make git     # hook in .gitconfig, set email + commit signing
make claude  # ask for the Azure DevOps org the MCP server needs (once per machine)

make macos       # macOS only: menu bar, Dock, Finder, trackpad, formats, file associations
make macos-hosts     # macOS only: install /etc/hosts from os/macos/system (asks for root)
make macos-touchid   # macOS only: authenticate sudo with Touch ID (asks for root)
make macos-xcode     # macOS only: select Xcode.app for xcodebuild, after make apps (asks for root)
make macos-spotlight-off  # macOS only: stop indexing files (asks for root) - see the Makefile
make jetbrains   # set the IDE heap; then open this repo in the IDE to get the plugins
make chrome      # Chrome's non-syncing toggles — quit Chrome first
```

- **`make apps` first** — `stow` is in the Brewfile. Homebrew on Linux too, so
  there is one package list instead of a Brewfile here and an apt list there;
  anything a distro does better stays with the distro behind `if OS.mac?`, and
  `os/<os-id>/install-apps.sh` picks up the GUI half that has no cask.
- **`make apps` ends with `make audit`** — what it just installed, checked for
  known vulnerabilities. It reports and carries on, so a CVE does not stop a
  new machine halfway; `make audit` on its own fails on one. `make apps` does
  not upgrade (`--no-upgrade`), so the fix it points to is `brew upgrade`.
- **New shell before `make stow`** — a just-installed brew is not on `PATH` yet:
  open a terminal, or `eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"`
  (macOS: `/opt/homebrew/bin/brew`).
- **`make shell` is bash only** — the stowed `~/.zshrc` loads the same
  `bash_aliases.d` drop-ins itself, and keeps `brew shellenv` where the repo can
  see it instead of an untracked `~/.zprofile`.
- **The IDE is last** — opening this repo offers every plugin in
  `.idea/externalDependencies.xml` in one click, and plugins are per IDE, not per
  project, so that one prompt covers every project on the machine.
- **`make chrome` needs Chrome quit, and Full Disk Access** — it rewrites
  `Default/Preferences` on exit, so a write made underneath it vanishes. macOS
  also guards that directory: without the terminal in System Settings > Privacy
  & Security > Full Disk Access, even listing it is `Operation not permitted`.
  Only the non-syncing toggles are patched; site permissions, history and the
  window rectangle are left alone.
- **Root-owned files are not installed by any of this** — see
  [devices/t480/system/README.md](../devices/t480/system/README.md).

## First run: existing files

A real file in `$HOME` where a symlink should go is renamed to
`<file>.bak.<timestamp>` and reported, then linked over — stow would otherwise
refuse and abort the whole package, stopping a fresh install at the first
hand-written dotfile. Nothing is deleted, so the machine's version is still next
to the symlink if it was the better one. See [bin/stow/backup.sh](../bin/stow/backup.sh).

To keep the machine's content instead, let stow adopt it — and **always check
`git diff` afterwards**, because this overwrites the repo's version with the
machine's:

```
stow --no-folding --adopt -t "$HOME" shared
stow --no-folding --adopt -t "$HOME" -d devices t480
git diff        # what the adopted files differ in — keep or discard
```
