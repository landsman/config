# Development tools

The editors, terminal and CLI tools I write code with, and where each one's
config lives. Everything under `shared/` reaches `$HOME` through `make stow`; the
binaries come from the [Brewfile](../Brewfile).

| Tool | Config | Notes |
|------|--------|-------|
| JetBrains IDEs | [`bin/jetbrains/`](../bin/jetbrains/README.md) | Installed by Toolbox, which owns the vmoptions — so the heap is patched by `make jetbrains`, not stowed. Plugins come from `.idea/externalDependencies.xml` |
| Zed | [`shared/.config/zed/settings.json`](../shared/.config/zed/settings.json) | See [below](#zed) |
| Ghostty | [`shared/.config/ghostty/config`](../shared/.config/ghostty/config) | One host can override it through an optional include, see [AGENTS.md](../AGENTS.md#a-one-machine-setting-stays-off-the-shared-config) |
| tmux | [`shared/.config/tmux/tmux.conf`](../shared/.config/tmux/tmux.conf) | vi keys, nothing else |
| television | [`shared/.config/television/config.toml`](../shared/.config/television/config.toml) | Only the keys that differ from tv's defaults; Ctrl-R stays hstr's |
| mise | [`shared/.config/mise/config.toml`](../shared/.config/mise/config.toml) | Global tools for a directory without its own `mise.toml`; Rust lives here, not in the Brewfile |
| Coding agents | [`.docs-llm/`](../.docs-llm/README.md) | Claude Code, opencode, Codex, Zed, Gemini — MCP servers, and where the files each one loads live |

## Zed

- **Extensions** install themselves from `auto_install_extensions`, so a new
  machine needs nothing but `make stow`.
- **`*.gradle.kts` is mapped to Kotlin**, because the java extension claims it as
  "Gradle KTS" and that grammar's highlights query fails to load, leaving the
  file uncoloured.
- **Edit predictions are off.** Copilot asks for the keychain password on every
  start, and having none keeps client code on the machine.
- **The agent panel runs Claude Code over ACP** (`agent_servers.claude-acp`), and
  reads the global rules through `~/.config/zed/AGENTS.md`, a symlink to
  `~/.agents/AGENTS.md`.
- **Extensions build for wasm32**, which is why Rust comes from mise through
  rustup rather than from Homebrew. `tree-sitter-cli` and `ts_query_ls` in the
  Brewfile are for telling a broken extension query from a file that does not
  parse.
- **macOS only for now.** The cask sits inside the `OS.mac?` guard, and the Linux
  half is not in `os/ubuntu/` yet.
