# Windows

The Windows 11 side of the [T480](../../devices/t480/README.md), which
triple-boots it next to Kubuntu and Omarchy. Nothing here is stowed. Windows
never runs `make stow`, and none of it is a dotfile. The package exists so the
Windows config is written down next to the other OSes rather than living only
in one machine's registry.

## Apply

On a fresh install, from an elevated PowerShell:

```
winget install --id Git.Git -e
git clone https://github.com/landsman/config
cd config
powershell -ExecutionPolicy Bypass -File os\windows\apply.ps1
```

Then restart once. Running it again changes nothing, so it is also how a
setting that drifted gets put back.

| Path | What |
|------|------|
| [`apply.ps1`](apply.ps1) | The one command: power plan, timeouts and power mode, then every `.reg` under `registry/` |
| [`registry/no-auto-reboot.reg`](registry/no-auto-reboot.reg) | Windows Update does not restart while I am signed in |

The values live at the top of `apply.ps1`, not in this README, so they cannot
drift apart. A new registry policy is a new `.reg` file in `registry/`, and the
script picks it up without an edit.

## Power

| Setting | Plugged in | On battery |
|---------|-----------|------------|
| Turn off the screen | never | 3 min |
| Sleep | never | 10 min |
| Hibernate | never | 3 h |
| Power mode | Balanced | Balanced |

Plugged in, the laptop works as a workstation, and a remote session to it must
not drop because it went to sleep. On battery the Windows defaults stay, so a
laptop forgotten in a bag still sleeps.

Power mode was **Best Performance** while plugged in, which kept the CPU
clocked up and the fan running constantly. Under Linux the same machine is
quiet. Balanced lets the CPU clock down again. The mode is stored as an overlay
GUID in `HKLM\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes`, and it
only applies on top of the Balanced power plan, which is why the script sets
that plan first.

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
prompt, then restart once. To check it took, go to Windows Update → Advanced options → Configured
update policies. The policy should be listed there.

To undo it, delete the `NoAutoRebootWithLoggedOnUsers` value in `regedit`.

If the notification policy above ever gets cleaned up, turn on **Notify me when
a restart is required to finish updating** in Advanced options. Until then that
toggle stays greyed out.
