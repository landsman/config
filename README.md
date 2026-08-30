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
| `os/ubuntu/` | Kubuntu userland — KDE, Dolphin, xdg portals — see [its README](os/ubuntu/README.md) | `make stow` (auto) |
| `os/arch/` | Omarchy/Arch userland — Hyprland, hyprmon | `make stow` (auto) |
| `os/macos/` | macOS userland — `~/.zshrc`: PATH, mise, completion | `make stow` (auto) |
| `devices/t480/system/` | Root-owned files under `/` for that machine — see [its README](devices/t480/system/README.md) | `sudo cp` (root, not stowable) |
| `.gitconfig` | Git settings, *included* into `~/.gitconfig` by absolute path | `make git` |
| `.bashrc` | Fragment *sourced* from the distro `~/.bashrc` by absolute path | `make shell` |
| `Brewfile` | Packages — one list for every machine, macOS and Linux | `make apps` |
| `bin/` | Setup that a symlink cannot express, one directory per tool, each with its own `*.test.sh` | its own `make` target |
| `AGENTS.md` | Conventions a coding agent follows here — `CLAUDE.md` is a symlink to it | loaded by the agent |
| `.docs-llm/` | Notes for this repo, not files for `$HOME` — [MCP servers](.docs-llm/mcp-servers.md) is a `claude mcp` cheat sheet, and [how the global rules reach each harness](.docs-llm/global-rules-and-skills.md) | read, not installed |

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
make apps    # Homebrew if missing, then the Brewfile (stow included), then
             # on Linux whatever the distro has to install itself
make stow    # symlink shared/ + the detected device and os packages into $HOME
make shell   # hook the alias loader into ~/.bashrc
make git     # hook in .gitconfig, set email + commit signing
make claude  # ask for the Azure DevOps org the MCP server needs (once per machine)

make macos       # macOS only: menu bar, Dock, Finder, trackpad, formats, file associations
make macos-touchid   # macOS only: authenticate sudo with Touch ID (asks for root)
make macos-spotlight-off  # macOS only: stop indexing files (asks for root) - see the Makefile
make jetbrains   # set the IDE heap; then open this repo in the IDE to get the plugins
```

- **`make apps` first** — `stow` is in the Brewfile. Homebrew on Linux too, so
  there is one package list instead of a Brewfile here and an apt list there;
  anything a distro does better stays with the distro behind `if OS.mac?`, and
  `os/<os-id>/install-apps.sh` picks up the GUI half that has no cask.
- **New shell before `make stow`** — a just-installed brew is not on `PATH` yet:
  open a terminal, or `eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"`
  (macOS: `/opt/homebrew/bin/brew`).
- **`make shell` is bash only** — the stowed `~/.zshrc` loads the same
  `bash_aliases.d` drop-ins itself, and keeps `brew shellenv` where the repo can
  see it instead of an untracked `~/.zprofile`.
- **The IDE is last** — opening this repo offers every plugin in
  `.idea/externalDependencies.xml` in one click, and plugins are per IDE, not per
  project, so that one prompt covers every project on the machine.
- **Root-owned files are not installed by any of this** — see
  [devices/t480/system/README.md](devices/t480/system/README.md).

### First run: existing files

A real file in `$HOME` where a symlink should go is renamed to
`<file>.bak.<timestamp>` and reported, then linked over — stow would otherwise
refuse and abort the whole package, stopping a fresh install at the first
hand-written dotfile. Nothing is deleted, so the machine's version is still next
to the symlink if it was the better one. See [bin/stow/backup.sh](bin/stow/backup.sh).

To keep the machine's content instead, let stow adopt it — and **always check
`git diff` afterwards**, because this overwrites the repo's version with the
machine's:

```
stow --no-folding --adopt -t "$HOME" shared
stow --no-folding --adopt -t "$HOME" -d devices t480
git diff        # what the adopted files differ in — keep or discard
```

## The semgrep mirror

`make security` scans this repo for leaked secrets and unsafe workflow config.
It pulls the scanner from `ghcr.io/landsman/semgrep-mirror`, not from Docker Hub,
which rate-limits anonymous pulls on the shared IPs CI runners come from.

That package is published from **this** repo and read by all of them. The address
carries no repo name, so any project pulls the same copy with no login once the
package is public; only this repo can push to it, because a `GITHUB_TOKEN` writes
only to packages under its own owner.

The version to mirror lives in one place, the `FROM` line of
`.github/semgrep-mirror.Dockerfile`, and everything else reads it from there —
`SEMGREP_VERSION` in the Makefile, and so the tag that gets pushed. It is written
literally rather than passed as a build arg because that is the only form
Dependabot can bump; it watches that file weekly and opens the pull request.

Merging that pull request is the whole procedure. The mirror workflow triggers on
pushes to `main` touching that path, so the new tag publishes itself. To bump by
hand, edit the `FROM` line — there is no version to type anywhere else, which is
the point: a version passed on a command line is a version no file records.

Two tags are pushed: the version, and `latest`. **The other repos pull `latest`,
this one pins the version.** That is what makes the bump above a decision taken
once rather than once per repo — `latest` here does not track semgrep's releases,
it tracks what this repo last merged, so a scanner reaches those repos only after
Dependabot proposed it, the cooldown aged it, and I approved it. The version tag
stays because it is what makes an old scan reproducible. The cost is real and
worth saying: merging here can turn a build red in another repo with no commit
there to point at, and this `git log` is where that explanation lives.

It is an unmodified copy of `semgrep/semgrep`, rebuilt only to carry
`org.opencontainers.image.source` pointing back here; upstream's label names
semgrep's own repository, which is what GitHub reads to decide where a package
belongs. `make semgrep-mirror` does the same thing from a laptop, given a
`docker login ghcr.io`. **A newly created package is private**, and a private one
is unreadable to the repos that pull it anonymously — flip it to public once, in
the package settings. Until a version is mirrored, `make security` falls back to
Docker Hub and says so.

## Notes

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
- **`~/.claude` is mostly runtime state** — sessions, caches, history. Only
  `CLAUDE.md`, `settings.json`, `voice.local.md` and the
  `.agents/skills/mcp-servers/`
  plugin — which is how the [MCP servers](.docs-llm/mcp-servers.md) get tracked,
  since neither `settings.json` nor `~/.claude.json` can hold them — are tracked,
  all in `shared/`; `--no-folding` keeps the directory real so nothing the tool writes
  lands here. `voice.local.md` is the odd one: the voice plugin rewrites it in
  place when you toggle voice, so a diff there is usually a toggle rather than a
  change worth committing.
- **The global rules are not Claude Code's alone** — `shared/.claude/rules/` is
  the single source, and each client points at it: Claude reads `~/.claude/CLAUDE.md`
  plus the `rules/` directory next to it, opencode reads
  `shared/.config/opencode/AGENTS.md` (an index that is not vendor-specific) and
  injects the same rule files through the `instructions` glob in its
  `opencode.json`. Skills live at `~/.agents/skills/`, the one location Codex
  and opencode both scan, with `~/.claude/skills` a symlink to it that `make
  stow` creates. The shape, and how a third harness plugs in, is in
  [.docs-llm](.docs-llm/global-rules-and-skills.md).
- **`settings.json` must hold no machine-specific path** — it is one file for
  every machine, and such a setting is not an error elsewhere, it is silently
  ignored. `make claude-settings-test` fails on a literal `/Users/` or `/home/`;
  use `~`. Anything genuinely local (a client checkout in
  `additionalDirectories`) goes in the untracked `~/.claude/settings.local.json`
  — that split is what keeps this repo safe to publish.

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
keyboard shortcuts, 16 of the 21 system ones turned off. That is a nested dict of
numeric IDs, so it is exported as XML and `defaults import`ed — readable as a diff,
where sixteen `-dict-add` lines would not be. One of the five left on is id 60,
*Select the previous input source*, on its stock `⌃Space` — the Czech/U.S. switch
is otherwise the left `fn` key, which an external keyboard does not have.
Re-export it with:

```
defaults export com.apple.symbolichotkeys bin/macos/symbolichotkeys.plist
plutil -convert xml1 bin/macos/symbolichotkeys.plist
```

**Which app opens what is a third shape again.** `make macos` also runs
`bin/macos/file-associations.sh`, which owns the *Open with… > Change All*
choices: `.sql` in Sublime Text, `.mp4` and `.m4a` in VLC, `.doc`, `.docx`,
`.xlsx` and `.csv` in LibreOffice, a saved `.html` in Chrome. The list is
`bin/macos/file-associations.conf`, a file of its own because it is the part
worth reading — three columns, and the first says which of the three keys macOS
matches on (`ext` an extension, `uti` a content type, `scheme` a URL scheme;
Finder picks, so copy what it wrote).

They all live in one `LSHandlers` array in
`~/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist`,
but writing that file is only half of it, and for a while it was the wrong half.
LaunchServices keeps its own copy of the content-type and URL-scheme bindings and
does not re-read the plist when its database is rebuilt, so an app that already
claims a type keeps it: Pages stayed the default for `.docx` while the plist said
LibreOffice. Those two kinds go through `LSSetDefaultRoleHandlerForContentType`
and `LSSetDefaultHandlerForURLScheme` instead, reached through `osascript`'s ObjC
bridge — the API `duti` wraps, without installing `duti`.

The plist is still written by hand for the `ext` kind, because that is the one
the API cannot express: for an extension no app claims a UTI for, it derives a
dynamic UTI and LaunchServices rejects it with `-50`, while Finder writes an
`LSHandlerContentTag` entry. The merge also leaves every other entry alone — the
rest of that array is a URL-scheme entry for every app the machine happens to
have installed, which is noise, not a choice. To add one: set it in Finder or
System Settings, read back what it wrote, and copy it into the list.

```
/usr/libexec/PlistBuddy -c 'Print :LSHandlers' ~/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist
```

The default browser is deliberately not in the list. It is the one association
macOS reserves for the user: `https` comes back `-54`, `http` is accepted and
then ignored, and the *Default web browser* dropdown is not a content type at all
(`-50`). Set it in System Settings > Desktop & Dock, once per machine.

`--dry-run` prints the merged plist and writes nothing. Applying rebuilds the
LaunchServices database, which takes a few seconds; without that an extension
would only arrive at the next login.

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
`os/ubuntu/.config/dolphinrc` will silently detach after KDE changes a setting.
`make restow` re-links it, and now backs the detached file up first rather than
failing — so commit the drift *before* running it if you meant to keep it,
otherwise it is a `.bak.<timestamp>` you have to go find.

## Docs

- [ThinkPad T480](devices/t480/README.md) — hardware, known issues, kernel pin
- [MacBook Pro 16" M5 Pro](devices/macbook-pro-m5-16/README.md) — hardware, what it stows
- [HP ProDesk 600 G3](devices/hp-prodesk-600-g3/README.md) — the pollos cluster, provisioned from [landsman/homelab](https://github.com/landsman/homelab/tree/main/pollos)
- [Omarchy/Arch userland](os/arch/README.md) — Hyprland config, and the AUR packages that stay out of the Brewfile
- [Kubuntu userland](os/ubuntu/README.md) — KDE config, and the apt packages that stay out of the Brewfile (1Password)
- [T480 system config (root-owned)](devices/t480/system/README.md)
- [JetBrains](bin/jetbrains/README.md) — Toolbox install, the plugin list, and why the IDE heap is patched rather than stowed
- [Coding agents](.docs-llm/README.md) — MCP server notes, and where the files an agent loads actually live
