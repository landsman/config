#
# GIT config
#
.PHONY: qa git-config-validate git-config-format

qa: git-config-validate

git-config-validate:
	# validate
	@git --no-pager config -f .gitconfig --list >/dev/null
	# format
	@tmp=$$(mktemp); sed -E 's/^[[:space:]]+/\t/' .gitconfig > $$tmp; \
	  diff -u .gitconfig $$tmp || { echo "run: make fmt-gitconfig"; rm $$tmp; exit 1; }; \
	  rm $$tmp

git-config-format:
	sed -i -E 's/^[[:space:]]+/\t/' .gitconfig
