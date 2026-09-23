# Windows

The Windows 11 side of the [T480](../../devices/t480/README.md), which
triple-boots it next to Kubuntu and Omarchy. Nothing here is stowed. Windows
never runs `make stow`, and none of it is a dotfile. The one piece of `shared/`
it does need, the agent config, `apply.ps1` links by hand; see
[Agent config](#agent-config). The package exists so the
Windows config is written down next to the other OSes rather than living only
in one machine's registry.

## Apply

On a fresh install, from an elevated PowerShell:

```
irm https://raw.githubusercontent.com/landsman/config/main/os/windows/bootstrap.ps1 | iex
```

That installs Git, clones this repo into `~\projects\landsman\config` (or
pulls it, if it is already there), and runs `apply.ps1`. Then restart once.
Running it again changes nothing, so it is also how a setting that drifted gets
put back. With the repo already cloned, `apply.ps1` on its own does the same:

```
powershell -ExecutionPolicy Bypass -File os\windows\apply.ps1
```

To try a branch before it is merged, set `$env:CONFIG_BRANCH = '<branch>'` and
swap `main` for the branch in the URL.

| Path | What |
|------|------|
| [`bootstrap.ps1`](bootstrap.ps1) | Git and the clone, for a machine that has neither, then `apply.ps1` |
| [`apply.ps1`](apply.ps1) | Power plan, timeouts and power mode, every `.reg` under `registry/`, the agent config links, then every app in `apps.txt` |
| [`apps.txt`](apps.txt) | The apps, as winget ids |
| [`CAVEATS.md`](CAVEATS.md) | What bites on Windows that the scripts do not or cannot fix: Smart App Control, `sh`, GRUB, first-run git and `gh` |
| [`forgejo-mcp.ps1`](forgejo-mcp.ps1) | Builds the Forgejo MCP server, asks for its token and registers it with Claude Code. Run by hand, not elevated |
| [`registry/no-auto-reboot.reg`](registry/no-auto-reboot.reg) | Windows Update does not restart while I am signed in |
| [`registry/no-fast-startup.reg`](registry/no-fast-startup.reg) | Shutting down really shuts down, so the Windows volume is closed cleanly for the Linux installs |

The values live at the top of `apply.ps1`, not in this README, so they cannot
drift apart. A new registry policy is a new `.reg` file in `registry/`, and the
script picks it up without an edit.

## Apps

[`apps.txt`](apps.txt) is the Windows counterpart of the Brewfile: one winget id
per line, and `apply.ps1` installs whichever are missing. It does not upgrade
them; `winget upgrade --all` does. One app that fails to install does not stop
the others, and the run ends with the list of those that failed.

| Not installable this way | Why | Instead |
|--------------------------|-----|---------|
| RustDesk | Removed from the winget repository | The installer from [its releases](https://github.com/rustdesk/rustdesk/releases) |

## Agent config

The rules, skills and Claude Code settings reach Windows the way they reach the
other OSes: as symlinks into this checkout, never copies. `apply.ps1` links
every entry of [`shared/.agents`](../../shared/.agents) into `~\.agents` and of
[`shared/.claude`](../../shared/.claude) into `~\.claude`, plus `~\.claude\rules`
and `~\.claude\skills` pointing at the shared rules and skills. That is the
layout [`global-rules-and-skills.md`](../../.docs-llm/global-rules-and-skills.md)
describes, with one difference: the rules and skills are linked as whole
directories, not file by file as stow does it, so a new one is live after a
`git pull` without running anything again.

A real file already in one of those places, such as a `settings.json` left by
an earlier install, is moved aside to `<name>.bak-<timestamp>`, not
overwritten.

`settings.json` is shared as is. Claude Code on Windows runs its shell commands,
the status line included, through Git Bash, which `bootstrap.ps1` installs
first. The two MCP servers in the `mcp-servers` skill that start through `sh`,
Azure DevOps and Forgejo, are the known gap: `sh` is not on the Windows `PATH`,
so they fail to connect there. The rest of the session is unaffected. Forgejo
has a Windows path of its own, described below. Azure DevOps is still the gap.

Creating a symlink on Windows needs an elevated shell or Developer Mode, which
is one more reason the script runs elevated. The clone in `bootstrap.ps1` sets
`core.symlinks=true` for the symlinks the repo itself tracks. A checkout cloned
without it keeps text files in their place until
`git config core.symlinks true` and a fresh checkout of those files.

## Forgejo MCP

[`forgejo-mcp.ps1`](forgejo-mcp.ps1) is the Windows half of `make forgejo-mcp`
and `make claude`. The Forgejo section of
[`mcp-servers.md`](../../.docs-llm/mcp-servers.md) explains the mirror, the
token scopes and the upload flag that stays off. Run it as yourself, not
elevated:

```
powershell -ExecutionPolicy Bypass -File os\windows\forgejo-mcp.ps1
```

It installs Git, Go and the Claude CLI through winget if any is missing. It
builds the newest stable tag from the mirror into `~\go\bin`. It asks for the
token and keeps it as the user environment variable `FORGEJO_ACCESS_TOKEN`, the
counterpart of the shell drop-in on the other OSes. Last, it registers the
server with `claude mcp add --scope user`, pointing straight at the `.exe`, so
no `sh` is involved. That user-scope `forgejo` shadows the skill's failing
entry of the same name. Restart Claude afterwards, so it picks up the new
environment variable.

### Smart App Control blocks the build

On the T480 the first build would not run: *An Application Control policy has
blocked this file*. The CodeIntegrity log (event 3118) names Smart App Control,
which is on and enforcing. It blocks every unsigned binary that Microsoft has no
reputation data for, and a binary built on the machine is always one. The
script checks that the binary runs before it registers anything, and stops
with a pointer here if it does not.

Smart App Control has **no allowlist**. There is no per-file or per-path
exception, and it ignores supplemental policies, so there is nothing to
whitelist from a script. The ways out:

| Option | Cost |
|--------|------|
| Turn Smart App Control off: Windows Security → App & browser control → Smart App Control | Loses the protection for everything else. On older builds it cannot be turned back on without a reinstall |
| Sign the binary with a publicly trusted code-signing certificate, such as Azure Trusted Signing | A paid certificate, and a signing step after every build. A self-signed certificate does not count |
| Run forgejo-mcp in WSL, where the Linux setup already works | WSL on the machine, and a Claude that runs there too |

Which one is a decision about the machine's security, so this repo does not
make it. Once Smart App Control is off, run the script again.

## Power

| Setting | Plugged in | On battery |
|---------|-----------|------------|
| Turn off the screen | never | 3 min |
| Sleep | never | 10 min |
| Hibernate | never | never |
| Fast Startup | off | off |
| Power mode | Balanced | Balanced |

Plugged in, the laptop works as a workstation, and a remote session to it must
not drop because it went to sleep. On battery it still sleeps, so a laptop
forgotten in a bag does not stay awake. It never hibernates on a timer, though.
See *Sleep turned into a reboot through GRUB* below.

Power mode was **Best Performance** while plugged in, which kept the CPU
clocked up and the fan running constantly. Under Linux the same machine is
quiet. Balanced lets the CPU clock down again. The mode is an overlay on top of
the Balanced power plan, which is why the script sets that plan first. It is
set with `powercfg /overlaysetactive`, not by writing the registry value
directly, because only SYSTEM may write that key. That command sets the mode
for whichever power source is in use, so run the script plugged in. The battery
side is Balanced by default; if Settings shows something else there, change it
once by hand.

## Windows Update restarted the machine mid-day, without warning

On 2026-09-23 the laptop restarted by itself during the day. Settings →
Windows Update → Update history showed the cause: that day's security update
(KB5129195) had installed, and Windows restarted to finish it.

It gave no warning because of two policies listed under Advanced options →
**Configured update policies**:

| Policy | Value |
|--------|-------|
| Display options for update notifications | `2`: turn off all notifications, including restart warnings |
| Turn off Auto Restart notification | `0`: disabled |

Both are labelled *Type: Mobile Device Management*, but the machine is not
enrolled anywhere. Tweaking and debloat tools write into the same policy store
(`HKLM\SOFTWARE\Microsoft\PolicyManager\current\device\Update`), and Settings
labels whatever it finds there as MDM. Where these two came from is not settled.

Active hours (14:00–05:00) do not cover this. They only protect the hours they
name, and outside them Windows restarts without asking.

### The fix

[`no-auto-reboot.reg`](registry/no-auto-reboot.reg) sets
`NoAutoRebootWithLoggedOnUsers = 1` under
`HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU`. Updates still
download and install. The restart waits until I do it, as long as anyone is
signed in. Security patches keep arriving, which is why this is the fix rather
than pausing updates. A pause runs out after five weeks, and until then it
skips the patches too.

`apply.ps1` imports it. On its own, double-click the file, accept the UAC
prompt, then restart once. To check it took, go to Windows Update → Advanced
options → Configured update policies. The policy should be listed there.

To undo it, delete the `NoAutoRebootWithLoggedOnUsers` value in `regedit`.

If the notification policy above ever gets cleaned up, turn on **Notify me when
a restart is required to finish updating** in Advanced options. Until then that
toggle stays greyed out.

## Sleep turned into a reboot through GRUB

On battery, waking the laptop sometimes went through the firmware and the GRUB
menu, where Windows had to be picked by hand, and then a slow "Resuming
Windows". The System event log from 2026-09-23 shows why:

| Time | Event |
|------|-------|
| 16:20 | Kernel-Power 42: entering sleep, reason *System Idle* |
| 19:20 | Kernel-Power 42: entering sleep, reason *Hibernate from Sleep - Fixed Timeout* |
| 20:33 | Kernel-Boot 27: boot type `0x2`, a resume from hibernation |

Sleep (S3) itself worked. Exactly three hours in, Windows woke up and
hibernated, because `hibernate-timeout-dc` was 180. That was the Windows
default, kept on purpose. To the firmware, a resume from hibernation is a cold
boot, so it goes through GRUB, and GRUB's default entry is Linux.

The timeout is now `0`, so sleep stays sleep for as long as the battery lasts.
Hibernation itself stays enabled, because it is the *critical battery action*
at 5%. Hibernating then is better than running flat with unsaved work, and it
happens only when the battery is nearly empty. Hibernate is also still in the
Start menu for anyone who wants it by hand.

### Fast Startup, for the other two OSes

[`no-fast-startup.reg`](registry/no-fast-startup.reg) sets
`HiberbootEnabled = 0`. With Fast Startup on, *Shut down* hibernates the kernel
instead of shutting down, and it leaves the Windows NTFS volume marked as in
use. Data gets lost if Linux writes to the volume in that state, or if Windows
resumes onto a volume Linux has changed. Linux's NTFS drivers refuse a
read-write mount of such a volume, but it is safer not to leave it in that state
at all. Now every shutdown closes the volume cleanly. The price is a boot that
is a few seconds slower.

The same care applies after a hibernation, whether by hand or at critical
battery. Resume Windows before booting Kubuntu or Omarchy, or at least do not
mount the Windows volume from Linux until it has.

To check: `powercfg /a` still lists *Hibernate* but no longer *Fast Startup*,
and `powercfg /q SCHEME_CURRENT SUB_SLEEP HIBERNATEIDLE` shows `0x00000000` for
both AC and DC.
