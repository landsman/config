# Config

Dotfiles and machine setup for macOS, Kubuntu, Arch and Windows, plus the rules
and skills my coding agents load.

- [Install](docs/install.md) — the `make` targets, their order, and adopting a machine's existing dotfiles
- [Layout](docs/layout.md) — what each directory holds and what installs it
- [How stow picks the packages](docs/packages.md) — device and OS detection, adding a machine
- [How the dotfiles are linked](docs/dotfiles.md) — `--no-folding`, why `.gitconfig` and `.bashrc` are not stowed, commit signing
- [macOS settings](docs/macos.md) — System Settings as `defaults`, shortcuts, file associations, Touch ID for `sudo`
- [The scanner mirrors](docs/scanner-mirrors.md) — semgrep and trivy from my GHCR, pinned by digest
- [Vulnerable dependencies](docs/vulnerable-dependencies.md) — the lockfile scan and Dependabot's security settings
- [Coding agents](.docs-llm/README.md) — what of the agent config is tracked, MCP servers, how the rules reach each harness

Machines and platforms:

- [ThinkPad T480](devices/t480/README.md) · [its root-owned files](devices/t480/system/README.md)
- [MacBook Pro 16" M5 Pro](devices/macbook-pro-m5-16/README.md)
- [HP ProDesk 600 G3](devices/hp-prodesk-600-g3/README.md) — provisioned from [landsman/homelab](https://github.com/landsman/homelab/tree/main/pollos)
- [Omarchy/Arch](os/arch/README.md) · [Kubuntu](os/ubuntu/README.md) · [Windows 11](os/windows/README.md)
- [JetBrains](bin/jetbrains/README.md)
