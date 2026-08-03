# JetBrains

```
make apps         # installs the Toolbox App (macOS cask); Linux notes below
make jetbrains    # sets the JVM options this repo owns, in every config dir found
make bin-test     # runs vmoptions.test.sh, along with every other bin/*/*.test.sh
```

## Plugins

[`.idea/externalDependencies.xml`](../../.idea/externalDependencies.xml) lists
the plugins this account uses. Open this repo in any JetBrains IDE and it offers
to install the missing ones in a single click — plugins are installed per IDE,
not per project, so that one prompt is the whole bootstrap. Nothing to run,
nothing to keep in sync with a marketplace API.

It is the only file under `.idea/` that is not gitignored.

The list is IDs, taken from the plugins directory of the IDE they were installed
in. To see what a machine actually has, and get the id of something new:

```
ls ~/Library/Application\ Support/JetBrains/<Version>/plugins   # macOS
ls ~/.local/share/JetBrains/<Version>                           # Linux
```

Bundled-but-downloaded plugins (PHP, Spring, Android, Junie…) live there too and
are listed alongside the marketplace ones, because on a fresh Ultimate they are
just as absent. A plugin already installed is skipped silently, so an entry
costs nothing on a machine that has it.

> The prompt names them "required plugins" and the notification is dismissible;
> it is a suggestion, not a gate. Nothing here refuses to open without them.

## Why a script and not a stow package

Two files decide an IDE's JVM options, and they **merge** — the launcher
concatenates them and the JVM takes the last value, so ours wins:

| File                                | Owner                                                                     |
| ----------------------------------- | ------------------------------------------------------------------------- |
| `<install>/bin/idea.vmoptions`      | JetBrains — ~25 lines of GC and module tuning, rewritten on every upgrade |
| `<config>/<Version>/idea.vmoptions` | us **and** Toolbox — the file `vmoptions.sh` patches                      |

> The [help page][tuning] says the config copy "will override the original
> file", which reads as replacement. It isn't: `collect_vm_options_from_files()`
> in the launcher extends the distribution options with the user's. Confirmed
> against `idea.log`, where all 25 install-directory lines appear before ours.
> Don't "fix" this script on the strength of that sentence.

The config file cannot be a symlink into this repo, because **Toolbox rewrites
it on every launch** to inject a notification token and a port path. Both are
per machine and per install — the T480 and the Mac have different ones — so a
symlink would push that straight back into git. `vmoptions.sh` therefore patches
only the lines this repo owns and leaves every other line where it found it.

Its path carries the IDE version (`…/IntelliJIdea2026.2/`), so a major upgrade
may need one rerun. `$IDEA_VM_OPTIONS` points at a user file from anywhere and
would be version-independent — it merges with the install file just like the
config one, so nothing goes stale — but it is not worth taking:

- it replaces the _Toolbox-written_ file, losing `-Dide.managed.by.toolbox` and
  the notification token, which is how Toolbox restarts the IDE after an update;
- it is per product — `WEBSTORM_VM_OPTIONS`, `PYCHARM_VM_OPTIONS`, one each;
- on macOS a Toolbox- or Finder-launched `.app` never sees a shell-exported
  variable, so it would need a LaunchAgent to be set at all.

In practice an upgrade copies the old config directory over, heap included; when
it doesn't, launch the new version once so the directory exists and re-run
`make jetbrains`.

[tuning]: https://www.jetbrains.com/help/idea/tuning-the-ide.html

Centralised vmoptions delivery does exist — [IDE Services][ide-services] pushes
settings and VM options to machines from a server — but it is the paid
enterprise product. Settings Sync does not cover vmoptions.

[ide-services]: https://www.jetbrains.com/help/ide-services/configure-settings-via-profiles.html

## What it sets

- `-Xmx8192m` — JetBrains ships 2048, which the indexer outgrows on a real
  project. `XMX` at the top of `vmoptions.sh`, or `--xmx` for one run.
- `-Dawt.toolkit.name=WLToolkit` — IDEA's native Wayland toolkit. Keyed on the
  running session rather than on the OS package, because the T480 boots more
  than one of those: added when `$WAYLAND_DISPLAY` is set, removed again when
  `$DISPLAY` is set without it, and left alone from a tty or over ssh, where
  neither says anything about how the IDE will be launched.

Both macOS (`~/Library/Application Support/JetBrains`) and Linux
(`~/.config/JetBrains`) are swept on every run, so one command is correct on
either; a path that does not exist contributes nothing.

## Installing Toolbox

macOS is in the [`Brewfile`](../../Brewfile) as `cask "jetbrains-toolbox"`.
Homebrew has no Linux cask, and Toolbox ships as a tarball there, so it stays
with the distro like the other AUR-only packages:

```
yay -S jetbrains-toolbox      # Arch
```

Sign in once per machine — the licence lives in a JetBrains account, not here.
