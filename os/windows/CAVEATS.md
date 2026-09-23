# Windows caveats

What bites on the Windows side of the [T480](../../devices/t480/README.md), and
what to do about it. Each one cost time once. The fixes this repo automates
live in [README.md](README.md). This file is for what it does not, or cannot.

## Smart App Control blocks anything built on the machine

A binary from `go install`, `cargo build` or similar fails with *An Application
Control policy has blocked this file*. The CodeIntegrity log
(Event Viewer → Applications and Services → Microsoft → Windows →
CodeIntegrity → Operational, event 3118) names Smart App Control. It blocks
every unsigned binary that Microsoft has no reputation data for, and a local
build always is one. The T480 shipped with it on and enforcing.

There is **no exception for a single app**. No per-file or per-path rule, no
"Run anyway", and a Defender exclusion does not reach it. The ways out:

| Option | Cost |
|--------|------|
| Turn it off | Off for every app. On many Windows 11 builds it cannot be turned back on without a clean reinstall |
| Sign the binary with a publicly trusted code-signing certificate, such as Azure Trusted Signing | A paid certificate, and a signing step after every build. A self-signed certificate does not count |
| Run the tool in WSL | Smart App Control does not apply there, and the Linux setup already works |

To turn it off, run `apply.ps1` with the switch, elevated, then restart:

```
powershell -ExecutionPolicy Bypass -File os\windows\apply.ps1 -DisableSmartAppControl
```

It sets `VerifiedAndReputablePolicyState = 0` under
`HKLM\SYSTEM\CurrentControlSet\Control\CI\Policy`, the value the Windows
Security toggle writes. `1` is on, `2` is evaluation, `0` is off. To see the
state:

```
reg query HKLM\SYSTEM\CurrentControlSet\Control\CI\Policy /v VerifiedAndReputablePolicyState
```

It is a switch, not a `.reg` file under `registry/`, because `apply.ps1`
imports all of those on every run. Switching off a security feature, often for
good, should be a decision made per machine, not a side effect of a fresh
install. A plain run leaves Smart App Control as it is.

## `sh` is not on `PATH`

Git for Windows puts only `Git\cmd` on the system `PATH`. Git Bash finds `sh`,
so Claude Code's own shell commands work. A process started straight from
Windows does not find it. Every MCP server in the shared `mcp-servers` skill
that starts through `sh -c` (Azure DevOps and Forgejo) fails to connect.

A Windows entry has to start the server's `.exe` directly, registered with
`claude mcp add --scope user`. A user-scope entry with the same name shadows
the skill's failing one.

## Anything that hibernates goes back through GRUB

To the firmware, a resume from hibernation is a cold boot, so it goes through
GRUB, and GRUB's default entry is Linux. Pick Windows by hand, and it resumes
where it left off. `apply.ps1` removes the hibernate timer and Fast Startup, so
this now happens only at critical battery or after a hibernation by hand. See
[Sleep turned into a reboot through GRUB](README.md#sleep-turned-into-a-reboot-through-grub).

While Windows is hibernated, its NTFS volume is still in use. Resume Windows
before booting Kubuntu or Omarchy, or at least do not mount that volume from
Linux until it has.

## Git has no identity on a fresh install

The repo's `.gitconfig` is stowed on the other OSes, and Windows never stows.
The first commit fails with *Author identity unknown*. Set it once:

```
git config --global user.name  "Michal Landsman"
git config --global user.email <the address in ~/.gitconfig on the other OSes>
```

## `gh auth login` needs a real terminal

`gh auth login --web` shows a one-time code, then waits for Enter before it
starts polling GitHub. Run from an agent's shell, or anywhere else without a
keyboard, it prints the code and never collects the approval. The code gets
approved in the browser, and `gh` still says *not logged in*. Run it in a
terminal you type into.

`git push` over HTTPS does not need `gh`. Git Credential Manager has its own
GitHub login, so a push can work while `gh` is still signed out.

## A winget install does not reach the open shell

winget updates the `PATH` in the registry, and only new shells read it. Open a
new terminal, or reload it in the one you have:

```
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
```

## `python` is a Microsoft Store stub until Python is installed

`C:\...\WindowsApps\python.exe` exists on a fresh install and opens the Store
instead of running anything. `Python.Python.3.14` from `apps.txt` goes onto the
`PATH` ahead of it. `where python` should list the `Programs\Python` copy first.

## Windows PowerShell 5.1 has sharp edges

The scripts here target the PowerShell every Windows ships, not PowerShell 7.

- **ASCII only.** A file without a BOM is read in the ANSI code page, so one
  typographic dash in a comment breaks parsing.
- **Stderr from a native tool is an error.** With `$ErrorActionPreference =
  'Stop'`, redirecting a native tool's stderr (`2>&1`, `2>$null`) turns each
  line into an error and stops the script, even when the tool exits 0. Lower
  the preference for that one call, or leave stderr alone.
- **`-NonInteractive` breaks `Read-Host`.** A script that prompts for a token
  cannot be tested from a shell started that way. It stops at the prompt.
