# Layout

Split on two axes — **device** and **OS** — because the same laptop multi-boots
Kubuntu and Arch (Omarchy), and the same OS runs on more than one machine. A file
lives wherever it stays true.

| Path | Scope | Installed by |
|------|-------|--------------|
| `shared/` | Portable — any machine, any OS | `make stow` |
| `devices/t480/` | This hardware, whichever OS is booted (Intel GPU, thinkpad_acpi) | `make stow` (auto) |
| `devices/macbook-pro-m5-16/` | The MacBook — nothing stowed yet, macOS-only machine | `make stow` (auto) |
| `os/ubuntu/` | Kubuntu userland — KDE, Dolphin, xdg portals — see [its README](../os/ubuntu/README.md) | `make stow` (auto) |
| `os/arch/` | Omarchy/Arch userland — Hyprland, hyprmon, shell plugins — see [its README](../os/arch/README.md) | `make stow` (auto), `make plugins` |
| `os/macos/` | macOS userland — `~/.zshrc`: PATH, mise, completion | `make stow` (auto) |
| `os/windows/` | Windows 11 on the T480 — apps, power settings and registry policies, see [its README](../os/windows/README.md) | `bootstrap.ps1`, not stowable |
| `devices/t480/system/` | Root-owned files under `/` for that machine — see [its README](../devices/t480/system/README.md) | `sudo cp` (root, not stowable) |
| `.gitconfig` | Git settings, *included* into `~/.gitconfig` by absolute path | `make git` |
| `.bashrc` | Fragment *sourced* from the distro `~/.bashrc` by absolute path | `make shell` |
| `Brewfile` | Packages — one list for every machine, macOS and Linux | `make apps` |
| `bin/` | Setup that a symlink cannot express, one directory per tool, each with its own `*.test.sh` | its own `make` target |
| `AGENTS.md` | Conventions a coding agent follows here — `CLAUDE.md` is a symlink to it | loaded by the agent |
| `.docs-llm/` | Notes for this repo, not files for `$HOME` — [MCP servers](../.docs-llm/mcp-servers.md) is a `claude mcp` cheat sheet, and [how the global rules reach each harness](../.docs-llm/global-rules-and-skills.md) | read, not installed |

How a machine is matched to its packages, and adding one: [packages.md](packages.md).
