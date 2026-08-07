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
tap "microsoft/sysinternalstap"

# Microsoft Azure CLI 2.0
brew "azure-cli"
# Resource monitor. C++ version and continuation of bashtop and bpytop
brew "btop"
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
# Kubernetes package manager
brew "helm"
# Kubernetes CLI To Manage Your Clusters In Style!
brew "k9s"
# Tool that can switch between kubectl contexts easily and create aliases
brew "kubectx"
# Kubernetes command-line interface
brew "kubernetes-cli"
# Lazier way to manage everything docker
brew "lazydocker"
# TUI for logs from journalctl, file system, Docker, Podman and Kubernetes pods
brew "lazyjournal"
# Postgres C API library
brew "libpq"
# Log file navigator
brew "lnav"
# Polyglot runtime manager (asdf rust clone)
brew "mise"
# Run multiple commands in parallel
brew "mprocs"
# Open-source, cross-platform JavaScript runtime environment
brew "node"
# AI coding agent, built for the terminal
brew "opencode"
# CLI for Postgres with auto-completion and syntax highlighting
brew "pgcli"
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

# Casks that ship a Linux build too, so they stay outside the guard below.
# Command-line interface for 1Password
cask "1password-cli"
# Open-source cross-platform alternative to AirDrop
cask "localsend"

# GUI apps — nearly every cask is macOS-only, so the rest are guarded. Anything
# the Linux boxes are better off getting from apt/pacman belongs in here too.
if OS.mac?
	# Password manager
	cask "1password"
	# Desktop client for ChatGPT
	cask "chatgpt"
	# Desktop client for Claude
	cask "claude"
	# Database GUI for PostgreSQL, MySQL and friends
	cask "dbeaver-community"
	# Voice, video and text chat
	cask "discord"
	# Container engine and GUI — the engine `lazydocker` above talks to
	cask "docker-desktop"
	# Collaborative design and prototyping
	cask "figma"
	# Fast, GPU-accelerated terminal emulator
	cask "ghostty"
	# Web browser — the default one, see bin/macos/file-associations.conf
	cask "google-chrome"
	# Terminal emulator as alternative to Apple's Terminal app
	cask "iterm2"
	# Installs and updates the JetBrains IDEs. It owns their vmoptions files, so
	# the heap this repo wants is applied by `make jetbrains` afterwards.
	cask "jetbrains-toolbox"
	# Office suite — opens the .doc, .docx and .xlsx associations
	cask "libreoffice"
	# macOS App for monitoring power usage and charging status
	cask "lzt1008/powerflow/powerflow", trusted: true
	# Team collaboration and meetings
	cask "microsoft-teams"
	# Screen zoom and annotation for presentations — Sysinternals ZoomIt
	cask "microsoft/sysinternalstap/zoomit"
	# Desktop client for Perplexity AI
	cask "perplexity"
	# Text editor for code, markup and prose
	cask "sublime-text"
	# Mesh VPN — the GUI app, the plain formula is CLI-only
	cask "tailscale-app"
	# Media player — opens the .mp4 and .m4a associations
	cask "vlc"
	# Video meetings and messaging
	cask "webex"
	# Desktop client for WhatsApp messaging
	cask "whatsapp"
	# Multiplayer code editor
	cask "zed"
end
