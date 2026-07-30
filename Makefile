SHELL := /bin/bash

# Dotfiles are stowed from three places, each mirroring $HOME:
#   .           shared/   portable, any machine + any OS
#   devices/    <device>  this hardware, whatever OS is booted
#   os/         <os-id>   OS/desktop userland
#
# Both are detected, so one `make stow` is correct on every install:
#   device from DMI product_version ("ThinkPad T480" -> t480)
#   os     from /etc/os-release ID  (ubuntu / arch)
# A name with no matching directory is skipped rather than failing, so a new
# machine works before its package exists. Override with:
#   make stow DEVICE=x1 OS=arch
#
# macOS has neither of those files, so it goes first: hw.model ("Mac17,8") is
# the only stable id, and it needs a name mapped onto it. Both are `?=`, so a
# DEVICE= on the command line still wins.
# ponytail: one Mac, one sed expression — add a line per machine, not a table.
ifeq ($(shell uname -s),Darwin)
DEVICE ?= $(shell sysctl -n hw.model | sed 's/^Mac17,8$$/macbook-pro-m5-16/')
OS     ?= macos
endif
DEVICE ?= $(shell awk '{print tolower($$NF)}' /sys/class/dmi/id/product_version 2>/dev/null)
OS     ?= $(shell . /etc/os-release 2>/dev/null && echo $$ID)

DEVICE_PKG := $(shell test -d 'devices/$(DEVICE)' && echo '$(DEVICE)')
OS_PKG     := $(shell test -d 'os/$(OS)' && echo '$(OS)')

STOW_FLAGS := --no-folding -t "$$HOME"

.PHONY: help
help: ## show this help
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | sed 's/:.*##/\t/'

#
# QA — every target here is read-only: it must not touch the machine it runs
# on, because CI runs the lot on macOS and Ubuntu on every pull request.
#

.PHONY: qa qa-deps lint bin-test
qa: qa-deps lint git-config-test apps-test stow-test bin-test ## run all checks — this is what CI runs

qa-deps:
	@# What the checks need, written down next to the checks, so ci.yml is just
	@# `make qa`. No `##`: it is part of qa, not a target to reach for.
	@# A runner is disposable and a laptop is not, so only CI gets to install
	@# anything — anywhere else this says the same thing `make stow` says.
	@# `brew install stow`, not `make apps`: the Brewfile is minutes of packages
	@# CI has no use for, and on Linux there is no brew to begin with.
	@command -v stow >/dev/null && command -v zsh >/dev/null && exit 0; \
	if [ -z "$$CI" ]; then echo "qa needs stow and zsh - run: make apps"; exit 1; \
	elif command -v brew >/dev/null; then brew install stow; \
	else sudo apt-get update && sudo apt-get install -y stow zsh; fi

lint: ## parse every shell file without running it
	@# -n is parse-only, so nothing here is sourced or executed. A typo in a
	@# stowed rc file otherwise surfaces as a broken login shell on the next
	@# machine, which is a bad place to find out.
	@for f in $$(git ls-files '*.sh' '.bashrc'); do echo "== $$f"; bash -n "$$f" || exit 1; done
	@# The zsh file gets the zsh parser: bash accepts most of it and would miss
	@# the rest (fpath arrays, autoload).
	@echo "== os/macos/.zshrc"; zsh -n os/macos/.zshrc

bin-test: ## run every *.test.sh — self-contained, no machine state touched
	@# `|| exit 1`, because a for loop exits with the status of its *last*
	@# iteration: without it a failure in any but the last test is reported green,
	@# and this is what CI gates on.
	@# os/ too, not just bin/: the distro installers stub apt and dpkg rather
	@# than touching them, so they run anywhere, including the macOS runner.
	@for t in bin/*/*.test.sh os/*/*.test.sh; do \
		echo "== $$t"; bash "$$t" || exit 1; \
	done

#
# Apps and packages — the Brewfile on every machine, plus whatever the distro
# has to supply itself. Called `apps` rather than `brew` because Homebrew is
# only most of it: the GUI half on Linux comes from vendor apt repos.
#

.PHONY: apps apps-test
apps: ## install Homebrew if missing, then the Brewfile, then the distro's own apps
	@command -v brew >/dev/null \
		|| /bin/bash -c "$$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
	@# A just-installed brew is not on PATH in *this* shell yet — the installer
	@# only adds it to the shell rc — so look where the two ports put it.
	@b=$$(command -v brew \
		|| ls /opt/homebrew/bin/brew /home/linuxbrew/.linuxbrew/bin/brew 2>/dev/null | head -1); \
		"$$b" bundle --file Brewfile
	@# The GUI half of the Brewfile is `if OS.mac?`, because a cask installs on
	@# Linux only when it ships a Linux build and almost no GUI app does. What
	@# the distro has to supply instead lives next to that OS's dotfiles, using
	@# the same $(OS) detection `make stow` uses. No file, nothing to do — which
	@# is how macOS skips this without a guard.
	@if [ -f 'os/$(OS)/install-apps.sh' ]; then bash 'os/$(OS)/install-apps.sh'; \
		else echo "no distro apps for os '$(OS)' - skipped"; fi

apps-test: ## parse the Brewfile without installing anything
	@# The Brewfile is Ruby, and `make apps` is the first thing a new machine
	@# runs — a syntax error there is found with no shell and no editor. `list`
	@# parses it and prints; it installs nothing and talks to no network.
	@command -v brew >/dev/null || { echo "brew not installed - skipped"; exit 0; }; \
		HOMEBREW_NO_AUTO_UPDATE=1 brew bundle list --file Brewfile >/dev/null

#
# Dotfiles ($HOME) via GNU stow
#

.PHONY: stow restow unstow stow-test
stow: ## symlink shared + device + os packages into $HOME (see README for first run)
	@command -v stow >/dev/null || { echo "stow not installed - run: make apps"; exit 1; }
	stow $(STOW_FLAGS) shared
	@# `if`, not `test && stow || echo`: with the latter a *failing stow* falls
	@# through to the echo and the target exits 0, reporting a conflict as
	@# "skipped".
	@if [ -n '$(DEVICE_PKG)' ]; then stow $(STOW_FLAGS) -d devices $(DEVICE_PKG); \
		else echo "no package for device '$(DEVICE)' - skipped"; fi
	@if [ -n '$(OS_PKG)' ]; then stow $(STOW_FLAGS) -d os $(OS_PKG); \
		else echo "no package for os '$(OS)' - skipped"; fi
	@echo "linked: shared $(DEVICE_PKG) $(OS_PKG)"

restow: ## re-link after adding files, or after an app replaced a symlink
	@command -v stow >/dev/null || { echo "stow not installed - run: make apps"; exit 1; }
	stow $(STOW_FLAGS) -R shared
	@if [ -n '$(DEVICE_PKG)' ]; then stow $(STOW_FLAGS) -R -d devices $(DEVICE_PKG); fi
	@if [ -n '$(OS_PKG)' ]; then stow $(STOW_FLAGS) -R -d os $(OS_PKG); fi

unstow: ## remove the symlinks again
	stow $(STOW_FLAGS) -D shared
	@if [ -n '$(DEVICE_PKG)' ]; then stow $(STOW_FLAGS) -D -d devices $(DEVICE_PKG); fi
	@if [ -n '$(OS_PKG)' ]; then stow $(STOW_FLAGS) -D -d os $(OS_PKG); fi

stow-test: ## stow and unstow every package in the repo into a throwaway $HOME
	@# Every package, not only this host's: a PR opened from the Mac would
	@# otherwise never look at devices/t480, and a file added to two packages is
	@# only a conflict once stow sees them together.
	@# Nothing outside the temp home is touched, so this is safe on a real
	@# machine and on a runner. `ls`, because a package whose .stow-local-ignore
	@# stopped covering docs/ and system/ is silent otherwise — stow links them
	@# into $HOME and exits 0.
	@set -e; trap 'rm -rf "$$t"' EXIT; \
	for p in devices/* os/*; do \
		case $$p in devices/*) v="DEVICE=$${p#devices/} OS=";; *) v="DEVICE= OS=$${p#os/}";; esac; \
		echo "== $$p"; t=$$(mktemp -d); \
		HOME=$$t $(MAKE) -s stow $$v; \
		ls "$$t" | grep -qxE 'docs|system|README.md' \
			&& { echo "$$p put a non-dotfile in \$$HOME - fix its .stow-local-ignore"; exit 1; } || true; \
		HOME=$$t $(MAKE) -s unstow $$v; rm -rf "$$t"; \
	done
	@# Once more with nothing overridden, so the DEVICE/OS detection this host
	@# uses is exercised too, not just the packages.
	@t=$$(mktemp -d); trap 'rm -rf "$$t"' EXIT; HOME=$$t $(MAKE) -s stow unstow

#
# Shell
#

.PHONY: shell
shell: ## source this repo's .bashrc fragment from ~/.bashrc (idempotent)
	@# Sourced by absolute path, the way .gitconfig is included, rather than
	@# appended: a copy stops tracking the repo the moment the fragment changes,
	@# and the old append-once grep would report success while doing nothing.
	@grep -qF '$(CURDIR)/.bashrc' "$$HOME/.bashrc" \
		|| printf '\n. "%s/.bashrc"\n' '$(CURDIR)' >> "$$HOME/.bashrc"
	@grep -nF '$(CURDIR)/.bashrc' "$$HOME/.bashrc"
	@grep -qF 'bash_aliases.d' "$$HOME/.bashrc" \
		&& echo "NOTE: an older copy of the fragment is still pasted into ~/.bashrc - delete that block, it shadows the repo" \
		|| true

#
# JetBrains IDEs — see bin/jetbrains/README.md for why this is a script, not stow
#

.PHONY: jetbrains
jetbrains: ## set the JVM options this repo owns in every JetBrains config dir
	./bin/jetbrains/vmoptions.sh
	@# The plugin half has no script to run: .idea/externalDependencies.xml makes
	@# the IDE offer to install the lot, and plugins are per IDE, not per project.
	@echo
	@echo "plugins: open $(CURDIR) in the IDE and accept the 'required plugins' prompt"

#
# macOS System Settings — the panes stow cannot reach, see bin/macos/defaults.sh
#

.PHONY: macos macos-touchid
macos: ## apply the macOS settings this repo owns (menu bar, Dock, Finder, trackpad)
	@[ "$$(uname -s)" = Darwin ] || { echo "macOS only - skipped"; exit 0; }; ./bin/macos/defaults.sh

macos-touchid: ## authenticate sudo with Touch ID (root-owned, so its own target)
	@# There is no System Settings toggle for this: the Touch ID pane covers the
	@# login window and Apple Pay, and sudo is PAM only. Apple ships the line
	@# commented out in a template that survives OS updates, so this uncomments
	@# that rather than writing a PAM file of its own.
	@# Not folded into `make macos`, which writes nothing outside $$HOME and asks
	@# for no password — this is the one thing here that needs root.
	@[ "$$(uname -s)" = Darwin ] || { echo "macOS only - skipped"; exit 0; }; \
	t=/etc/pam.d/sudo_local.template; f=/etc/pam.d/sudo_local; \
	if [ -f "$$f" ] && grep -q '^auth.*pam_tid.so' "$$f"; then echo "already enabled: $$f"; exit 0; fi; \
	[ -f "$$t" ] || { echo "no $$t - needs macOS 14 or newer"; exit 1; }; \
	tmp=$$(mktemp); sed 's/^#auth\(.*pam_tid\.so\)/auth\1/' "$$t" > "$$tmp"; \
	grep -q '^auth[[:space:]]*sufficient[[:space:]]*pam_tid\.so' "$$tmp" \
		|| { rm -f "$$tmp"; echo "the template is not what this expects - enable it by hand"; exit 1; }; \
	echo "sudo is about to be reconfigured - keep this terminal open until it is verified"; \
	sudo install -m 444 -o root -g wheel "$$tmp" "$$f"; rm -f "$$tmp"; \
	cat "$$f"; \
	sudo -k; echo "now run any sudo command - it should ask for a fingerprint"

#
# GIT config
#

.PHONY: git git-config-test git-config-format
git: ## set up this machine: hook in .gitconfig, set email, set up commit signing
	@git config --global --get-all include.path | grep -qxF '$(CURDIR)/.gitconfig' \
		|| git config --global --add include.path '$(CURDIR)/.gitconfig'
	@read -p "email [$$(git config --file '$(CURDIR)/.gitconfig' user.email)]: " e; \
		[ -z "$$e" ] || git config --global user.email "$$e"
	@email="$$(git config user.email)"; \
		case "$$email" in ""|*"*"*) echo "set a real user.email first - the repo default is a placeholder"; exit 1;; esac; \
		default="$$HOME/.ssh/landsman_git_signing.pub"; \
		read -p "signing key [$$default]: " k; k="$${k:-$$default}"; \
		priv="$${k%.pub}"; \
		if [ ! -f "$$priv" ]; then \
			echo "no key at $$priv"; \
			echo "restore it from 1Password, chmod 600 it, then run make git again"; \
			exit 1; \
		fi; \
		signers="$$HOME/.ssh/allowed_signers"; \
		git config --global user.signingkey "$$k"; \
		git config --global gpg.ssh.allowedSignersFile "$$signers"; \
		touch "$$signers"; \
		line="$$email $$(cut -d" " -f1,2 "$$k")"; \
		grep -qxF "$$line" "$$signers" || echo "$$line" >> "$$signers"; \
		echo; echo "add as a *signing* key at https://github.com/settings/ssh/new :"; \
		cat "$$k"
	@git config --list --show-scope

git-config-test: ## check .gitconfig parses and is tab-indented
	@# validate
	@git --no-pager config -f .gitconfig --list >/dev/null
	@# format
	@tmp=$$(mktemp); sed -E 's/^[[:space:]]+/\t/' .gitconfig > $$tmp; \
	  diff -u .gitconfig $$tmp || { echo "run: make git-config-format"; rm $$tmp; exit 1; }; \
	  rm $$tmp

git-config-format: ## reindent .gitconfig with tabs
	sed -i -E 's/^[[:space:]]+/\t/' .gitconfig

.DEFAULT_GOAL := help
