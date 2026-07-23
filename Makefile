SHELL := /bin/bash

help: ## show this help
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | sed 's/:.*##/\t/'

git: ## hook repo .gitconfig into ~/.gitconfig, ask for email override
	@git config --global --get-all include.path | grep -qxF '$(CURDIR)/.gitconfig' \
		|| git config --global --add include.path '$(CURDIR)/.gitconfig'
	@read -p "email [$$(git config --file '$(CURDIR)/.gitconfig' user.email)]: " e; \
		[ -z "$$e" ] || git config --global user.email "$$e"
	@git config --show-origin --get-all include.path
	@git config --show-origin user.email

.DEFAULT_GOAL := help
.PHONY: help git
