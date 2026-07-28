# Packages, installed by `make brew` (which installs Homebrew itself if needed).
#
# Shared by macOS and Linux — Homebrew runs on both, so the CLI tooling is the
# same everywhere and only the GUI half is guarded. A Brewfile is Ruby, so the
# guard is just `if OS.mac?`; use it for anything the Linux boxes are better off
# getting from apt/pacman.
#
# Refresh after installing something new — note it overwrites this file, so
# re-add the guards afterwards:
#   brew bundle dump --force --no-vscode

tap "lzt1008/powerflow"

# Microsoft Azure CLI 2.0
brew "azure-cli"
# Incredibly fast JavaScript runtime, bundler, test runner, and package manager
brew "bun"
# Securely send things from one computer to another
brew "croc"
# Secure runtime for JavaScript and TypeScript
brew "deno"
# Play, record, convert, and stream select audio and video codecs
brew "ffmpeg"
# GitHub command-line tool
brew "gh"
# Bash and zsh history suggest box
brew "hstr"
# Open source programming language to build simple/reliable/efficient software
brew "go"
# Lazier way to manage everything docker
brew "lazydocker"
# TUI for logs from journalctl, file system, Docker, Podman and Kubernetes pods
brew "lazyjournal"
# Postgres C API library
brew "libpq"
# Polyglot runtime manager (asdf rust clone)
brew "mise"
# Run multiple commands in parallel
brew "mprocs"
# Open-source, cross-platform JavaScript runtime environment
brew "node"
# AI coding agent, built for the terminal
brew "opencode"
# Fast, disk space efficient package manager
brew "pnpm"
# PDF rendering library (based on the xpdf-3.0 code base)
brew "poppler"
# Rsync for cloud storage
brew "rclone"
# Utility that provides fast incremental file transfer
brew "rsync"
# Symlink farm manager — this repo's `make stow` needs it
brew "stow"
# General purpose fuzzy finder TUI
brew "television"
# Terminal multiplexer
brew "tmux"
# Extremely fast Python package installer and resolver, written in Rust
brew "uv"
# Blazing fast terminal file manager written in Rust, based on async I/O
brew "yazi"
# Unified toolchain and entry point for web development
brew "vite-plus"

# Apple Silicon Monitor Top written in Go Lang
brew "mactop" if OS.mac?
# Real-time type-ahead completion for Zsh — the Linux boxes are bash, see .bashrc
brew "zsh-autocomplete" if OS.mac?

# GUI apps — casks are macOS-only, Homebrew on Linux has none.
if OS.mac?
	# Terminal emulator as alternative to Apple's Terminal app
	cask "iterm2"
	# Installs and updates the JetBrains IDEs. It owns their vmoptions files, so
	# the heap this repo wants is applied by `make jetbrains` afterwards.
	cask "jetbrains-toolbox"
	# Open-source cross-platform alternative to AirDrop
	cask "localsend"
	# macOS App for monitoring power usage and charging status
	cask "lzt1008/powerflow/powerflow", trusted: true
end
