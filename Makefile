.PHONY: qa validate-gitconfig

qa: validate-gitconfig

validate-gitconfig:
	git --no-pager config -f .gitconfig --list
