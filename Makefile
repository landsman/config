SHELL := /bin/bash

.PHONY: help qa git git-config-validate git-config-format

help: ## show this help
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | sed 's/:.*##/\t/'

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
