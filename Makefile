SHELL := /bin/bash

.PHONY: help qa git git-config-validate git-config-format stow restow unstow shell

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

help: ## show this help
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | sed 's/:.*##/\t/'

#
# Dotfiles ($HOME) via GNU stow
#

stow: ## symlink shared + device + os packages into $HOME (see README for first run)
	@command -v stow >/dev/null || { echo "stow not installed: apt install stow / brew install stow"; exit 1; }
	stow $(STOW_FLAGS) shared
	@test -n '$(DEVICE_PKG)' && stow $(STOW_FLAGS) -d devices $(DEVICE_PKG) \
		|| echo "no package for device '$(DEVICE)' - skipped"
	@test -n '$(OS_PKG)' && stow $(STOW_FLAGS) -d os $(OS_PKG) \
		|| echo "no package for os '$(OS)' - skipped"
	@echo "linked: shared $(DEVICE_PKG) $(OS_PKG)"

restow: ## re-link after adding files, or after an app replaced a symlink
	@command -v stow >/dev/null || { echo "stow not installed: apt install stow / brew install stow"; exit 1; }
	stow $(STOW_FLAGS) -R shared
	@test -n '$(DEVICE_PKG)' && stow $(STOW_FLAGS) -R -d devices $(DEVICE_PKG) || true
	@test -n '$(OS_PKG)' && stow $(STOW_FLAGS) -R -d os $(OS_PKG) || true

unstow: ## remove the symlinks again
	stow $(STOW_FLAGS) -D shared
	@test -n '$(DEVICE_PKG)' && stow $(STOW_FLAGS) -D -d devices $(DEVICE_PKG) || true
	@test -n '$(OS_PKG)' && stow $(STOW_FLAGS) -D -d os $(OS_PKG) || true

shell: ## hook the alias loader into ~/.bashrc (idempotent)
	@grep -qF 'bash_aliases.d' "$$HOME/.bashrc" \
		|| cat .bashrc >> "$$HOME/.bashrc"
	@grep -nF 'bash_aliases.d' "$$HOME/.bashrc"

#
# GIT config
#

qa: git-config-validate ## run all checks

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

git-config-validate: ## check .gitconfig parses and is tab-indented
	@# validate
	@git --no-pager config -f .gitconfig --list >/dev/null
	@# format
	@tmp=$$(mktemp); sed -E 's/^[[:space:]]+/\t/' .gitconfig > $$tmp; \
	  diff -u .gitconfig $$tmp || { echo "run: make git-config-format"; rm $$tmp; exit 1; }; \
	  rm $$tmp

git-config-format: ## reindent .gitconfig with tabs
	sed -i -E 's/^[[:space:]]+/\t/' .gitconfig

.DEFAULT_GOAL := help
