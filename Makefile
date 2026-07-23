SHELL := /bin/bash

.PHONY: help qa git git-config-validate git-config-format

help: ## show this help
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | sed 's/:.*##/\t/'

#
# GIT config
#

qa: git-config-validate ## run all checks

git: ## hook repo .gitconfig into ~/.gitconfig, ask for email override
	@git config --global --get-all include.path | grep -qxF '$(CURDIR)/.gitconfig' \
		|| git config --global --add include.path '$(CURDIR)/.gitconfig'
	@read -p "email [$$(git config --file '$(CURDIR)/.gitconfig' user.email)]: " e; \
		[ -z "$$e" ] || git config --global user.email "$$e"
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
