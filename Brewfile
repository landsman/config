# Packages, installed by `make brew` (which installs Homebrew itself if needed).
#
# Shared by macOS and Linux — Homebrew runs on both, so the CLI tooling is the
# same everywhere and only the GUI half is guarded. A Brewfile is Ruby, so the
# guard is just `if OS.mac?`; use it for anything the Linux boxes are better off
# getting from apt/pacman.
#
# Refresh after installing something new — note it overwrites this file, so
# re-add the guards and the `trusted:` options afterwards:
#   brew bundle dump --force --no-vscode

# hashicorp's is unguarded because terraform below is wanted on both; the other
# three serve `if OS.mac?` entries only, and a tap cloned onto a box that will
# never install from it is also a tap whose trust is never recorded — which
# brew reports on every command until it is untapped.
tap "hashicorp/tap"
tap "lzt1008/powerflow" if OS.mac?
tap "microsoft/sysinternalstap" if OS.mac?
tap "stripe/stripe-cli" if OS.mac?

# Resource monitor. C++ version and continuation of bashtop and bpytop
brew "btop"
# Incredibly fast JavaScript runtime, bundler, test runner, and package manager
brew "bun"
# Command-line tool to manage Cloudflare Tunnel connections
brew "cloudflared"
# Securely send things from one computer to another
brew "croc"
# Secure runtime for JavaScript and TypeScript
brew "deno"
# ls with colour per file type, icons and a git column — aliased in 00-general.sh
brew "eza"
# Play, record, convert, and stream select audio and video codecs
brew "ffmpeg"
# GitHub command-line tool
brew "gh"
# Distributed revision control — a current one on both platforms, not the
# Xcode tools copy on macOS or whatever the distro froze
brew "git"
# Large file storage — .gitconfig sets the lfs filter as required, so an LFS
# repo will not even clone without it
brew "git-lfs"
# GitLab command-line tool
brew "glab"
# Bash and zsh history suggest box
brew "hstr"
# Interactive process viewer — the one every host already knows, beside btop
brew "htop"
# Unpack installers created by Inno Setup, without running them on Windows
# https://github.com/dscharrer/innoextract
brew "innoextract"
# Open source programming language to build simple/reliable/efficient software
brew "go"
# JSON processor — the checkout guard hook reads Claude Code's input with it,
# and macOS ships it while Kubuntu does not
brew "jq"
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
# HEIF/HEIC decoder and encoder. Here for Go development: reading images in the
# format phones now shoot by default, and rendering thumbnails from them.
# https://github.com/strukturag/libheif is this C library and the Go binding in
# one repo — the binding is cgo, so `go build` stops at pkg-config without it.
brew "libheif"
# Postgres C API library
brew "libpq"
# Log file navigator
brew "lnav"
# Polyglot runtime manager (asdf rust clone)
brew "mise"
# Process manager for dev and prod — `mprocs` until upstream renamed it, and
# the old name still resolves but warns on every `brew bundle`
brew "dekit"
# Open-source, cross-platform JavaScript runtime environment
brew "node"
# Create, run, and share large language models (LLMs)
brew "ollama"
# AI coding agent, built for the terminal
brew "opencode"
# CLI for Postgres with auto-completion and syntax highlighting
brew "pgcli"
# Fast, disk space efficient package manager. Yarn has no line of its own here:
# the formula is still 1.22, and corepack — the way to a Berry one — ships a
# pnpm shim that collides with this, so `make apps` installs it out of the way.
brew "pnpm"
# PDF rendering library (based on the xpdf-3.0 code base)
brew "poppler"
# Rsync for cloud storage
brew "rclone"
# Utility that provides fast incremental file transfer
brew "rsync"
# Proxy server that works as a poor man's VPN — tunnels over plain ssh, so it
# reaches a network where nothing but sshd is exposed
brew "sshuttle"
# Symlink farm manager — this repo's `make stow` needs it
brew "stow"
# Gitea command-line tool — also speaks to Forgejo, the forge gh and glab
# cannot reach
brew "tea"
# General purpose fuzzy finder TUI
brew "television"
# Infrastructure as code — vendor tap, homebrew-core dropped it over the BSL.
# `trusted: true` on every entry from a third-party tap, because Homebrew now
# refuses to load one until it is trusted: without it `make apps` stops with
# "Refusing to load formula ... from untrusted tap" and a `brew trust` command
# to go and run by hand. The option makes bundle record that trust itself, so
# the decision lives in this file — where the tap it applies to is written down
# — rather than in a one-off command on each machine. homebrew-core is trusted
# already, so nothing above needs it.
brew "hashicorp/tap/terraform", trusted: true
# Terminal multiplexer
brew "tmux"
# Tree-sitter CLI — parse a file and run a highlight or outline query against a
# grammar, to tell an editor's broken query from a file that does not parse
brew "tree-sitter-cli"
# Formatter and linter for tree-sitter queries (.scm), what editor extensions
# such as Zed's run in their own `fmt`
brew "ts_query_ls"
# Extremely fast Python package installer and resolver, written in Rust
brew "uv"
# Speech to text on this machine — transcribes a call, see bin/calls/transcribe.ts
brew "whisper.cpp"
# Blazing fast terminal file manager written in Rust, based on async I/O
brew "yazi"
# Unified toolchain and entry point for web development
brew "vite-plus"

# Apple Silicon Monitor Top written in Go Lang
brew "mactop" if OS.mac?
# Apple's own container runtime, each container in its own lightweight VM.
# Apple silicon and macOS 26 only. The first `container system start` offers
# to fetch the Linux kernel it boots; `--enable-kernel-install` skips the ask.
brew "container" if OS.mac?
# App Store CLI — what the `mas` lines at the end install through
brew "mas" if OS.mac?
# Stripe CLI. Guarded because the tap's formula is `depends_on :macos` — the
# Linux boxes take it from packages.stripe.dev, see os/ubuntu/install-apps.sh.
# It also installs its own shell completions into share/{zsh,bash}, both already
# on the path `brew shellenv` sets up, which is why neither rc file mentions it.
# The `stripe completion` command prints a ~/.stripe recipe instead; ignore it.
brew "stripe/stripe-cli/stripe", trusted: true if OS.mac?
# Real-time type-ahead completion for Zsh — the Linux boxes are bash, see .bashrc
brew "zsh-autocomplete" if OS.mac?

# Casks that ship a Linux build too, so they stay outside the guard below.
# Command-line interface for 1Password
cask "1password-cli"
# Microsoft Azure CLI 2.0. A cask rather than a formula: homebrew-core migrated
# it to homebrew-cask, which installs Microsoft's own build instead of building
# the Python tree. Here rather than inside the guard because that build is per
# platform — the url resolves to the linux-x86_64 tarball on the Linux boxes —
# and the only artifact is `bin/az` plus its completions, nothing macOS-shaped.
cask "azure-cli"
# Open-source cross-platform alternative to AirDrop
cask "localsend"
# Open-source remote desktop
cask "rustdesk"

# GUI apps — nearly every cask is macOS-only, so the rest are guarded. Anything
# the Linux boxes are better off getting from apt/pacman belongs in here too.
if OS.mac?
	# Password manager
	cask "1password"
	# Keeps the Mac awake from the menu bar
	cask "caffeine"
	# Desktop client for ChatGPT
	cask "chatgpt"
	# Desktop client for Claude
	cask "claude"
	# Database GUI for PostgreSQL, MySQL and friends
	cask "dbeaver-community"
	# Finds apps a planted dylib could hijack, from Objective-See
	cask "dhs"
	# Voice, video and text chat
	cask "discord"
	# Container engine and GUI — the engine `lazydocker` above talks to
	cask "docker-desktop"
	# Collaborative design and prototyping
	cask "figma"
	# The icons eza draws, for terminals that do not bundle them. Ghostty does,
	# which is why the Linux boxes go without.
	cask "font-jetbrains-mono-nerd-font"
	# Fast, GPU-accelerated terminal emulator
	cask "ghostty"
	# Web browser — the default one, see bin/macos/file-associations.conf
	cask "google-chrome"
	# Web browser for the `ai-e2e` instance the agents drive. Only its own bundle
	# id keeps LaunchServices from routing my links into it; the reasoning is in
	# shared/.agents/rules/browser-automation.md
	cask "google-chrome@canary"
	# Terminal emulator as alternative to Apple's Terminal app
	cask "iterm2"
	# Installs and updates the JetBrains IDEs. It owns their vmoptions files, so
	# the heap this repo wants is applied by `make jetbrains` afterwards.
	cask "jetbrains-toolbox"
	# Remaps keys per app — makes ⌘ + forward delete trash a file in Finder, see
	# os/macos/.config/karabiner. Needs its driver and Input Monitoring approved once.
	cask "karabiner-elements"
	# Office suite — opens the .doc, .docx and .xlsx associations
	cask "libreoffice"
	# Firewall that asks before an app makes an outgoing connection
	cask "lulu"
	# macOS App for monitoring power usage and charging status
	cask "lzt1008/powerflow/powerflow", trusted: true
	# Team collaboration and meetings
	cask "microsoft-teams"
	# Screen zoom and annotation for presentations — Sysinternals ZoomIt
	cask "microsoft/sysinternalstap/zoomit", trusted: true
	# Screen and audio recorder — records a call, see bin/calls/record.ts
	cask "obs"
	# Terminal built for coding agents (closed source)
	cask "otty"
	# Desktop client for Perplexity AI
	cask "perplexity"
	# Text editor for code, markup and prose
	cask "sublime-text"
	# Mesh VPN — the GUI app, the plain formula is CLI-only
	cask "tailscale-app"
	# Messaging — the native macOS client, deliberately not the `telegram-desktop`
	# cask. The Linux boxes get the Qt one from Flathub, see os/ubuntu.
	cask "telegram"
	# Media player — opens the .mp4 and .m4a associations
	cask "vlc"
	# Video meetings and messaging
	cask "webex"
	# Desktop client for WhatsApp messaging
	cask "whatsapp"
	# Multiplayer code editor
	cask "zed"

	# App Store apps, by the id in their store URL. `mas` cannot sign in for you:
	# open the App Store and sign in first, or `make apps` stops here. Why none of
	# them installs on Linux is in os/ubuntu/README.md.
	mas "Azure VPN Client", id: 1553936137
	mas "ColorSlurp", id: 1287239339
	mas "iMovie", id: 408981434
	mas "Infuse", id: 1136220934
	mas "Keynote", id: 361285480
	mas "Numbers", id: 361304891
	mas "OpenDisk", id: 6793260558
	mas "Pages", id: 361309726
	mas "Tasks.txt", id: 6783916102
	mas "The Unarchiver", id: 425424353
	mas "Toggl Track", id: 1291898086
	# Selected as the active developer dir by `make macos-xcode`
	mas "Xcode", id: 497799835
end
