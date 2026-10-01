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
| `os/windows/` | Windows 11 on the T480 — apps, power settings and registry policies, see [its README](os/windows/README.md) | `bootstrap.ps1`, not stowable |
| `devices/t480/system/` | Root-owned files under `/` for that machine — see [its README](devices/t480/system/README.md) | `sudo cp` (root, not stowable) |
| `.gitconfig` | Git settings, *included* into `~/.gitconfig` by absolute path | `make git` |
| `.bashrc` | Fragment *sourced* from the distro `~/.bashrc` by absolute path | `make shell` |
| `Brewfile` | Packages — one list for every machine, macOS and Linux | `make apps` |
| `bin/` | Setup that a symlink cannot express, one directory per tool, each with its own `*.test.sh` | its own `make` target |
| `AGENTS.md` | Conventions a coding agent follows here — `CLAUDE.md` is a symlink to it | loaded by the agent |
| `.docs-llm/` | Notes for this repo, not files for `$HOME` — [MCP servers](.docs-llm/mcp-servers.md) is a `claude mcp` cheat sheet, and [how the global rules reach each harness](.docs-llm/global-rules-and-skills.md) | read, not installed |

How a machine is matched to its packages, and adding one: [docs/packages.md](docs/packages.md).

## Install

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
make audit       # known vulnerabilities in what this machine has installed
```

Order, prerequisites, and what to do when `$HOME` already has the files:
[docs/install.md](docs/install.md).

## Docs

By topic:

- [Install](docs/install.md) — the order that works, what each step needs, and adopting a machine's existing dotfiles
- [How stow picks the packages](docs/packages.md) — device and OS detection, overriding it, adding a machine
- [How the dotfiles are linked](docs/dotfiles.md) — `--no-folding`, why `.gitconfig` and `.bashrc` are not stowed, commit signing through the agent, KDE files that detach
- [macOS settings](docs/macos.md) — System Settings as `defaults`, the keyboard shortcuts, file associations, Touch ID for `sudo`
- [The scanner mirrors](docs/scanner-mirrors.md) — semgrep and trivy from my GHCR, pinned by digest, bumped by Dependabot
- [Vulnerable dependencies](docs/vulnerable-dependencies.md) — the lockfile scan and Dependabot's security settings
- [What of the agent config is tracked](.docs-llm/agent-config.md) — `~/.claude`, the global rules, and keeping `settings.json` machine-independent

By machine and tool:

- [ThinkPad T480](devices/t480/README.md) — hardware, known issues, kernel pin
- [MacBook Pro 16" M5 Pro](devices/macbook-pro-m5-16/README.md) — hardware, what it stows
- [HP ProDesk 600 G3](devices/hp-prodesk-600-g3/README.md) — the pollos cluster, provisioned from [landsman/homelab](https://github.com/landsman/homelab/tree/main/pollos)
- [Omarchy/Arch userland](os/arch/README.md) — Hyprland config, and the AUR packages that stay out of the Brewfile
- [Kubuntu userland](os/ubuntu/README.md) — KDE config, and the apt packages that stay out of the Brewfile (1Password)
- [Windows 11](os/windows/README.md) — one command for apps, power settings and policies, and why Windows Update no longer restarts while I am signed in
- [T480 system config (root-owned)](devices/t480/system/README.md)
- [JetBrains](bin/jetbrains/README.md) — Toolbox install, the plugin list, and why the IDE heap is patched rather than stowed
- [Coding agents](.docs-llm/README.md) — MCP server notes, and where the files an agent loads actually live
