#!/usr/bin/env bash
# Back up ~/.ssh/config to 1Password, and restore it, keyed by the machine's own
# hostname so neither end needs a title typed. The file is machine-specific —
# different Host blocks per box — and holds a client's internal network, so it
# belongs in 1Password rather than this public repo.
#
#   config-1password.sh backup    # create the item, or update it if it exists
#   config-1password.sh restore   # write this machine's item back to ~/.ssh/config
#
# Needs the 1Password CLI signed in: `eval "$(op signin)"`, or the desktop app's
# CLI integration. `make apps` installs op (os/ubuntu/install-apps.sh, or the
# Brewfile cask on the Mac).
set -euo pipefail

title="ssh-config-$(hostname -s)"
file="$HOME/.ssh/config"

command -v op >/dev/null || { echo "op (1Password CLI) not found - run: make apps" >&2; exit 1; }

case "${1:-}" in
backup)
	[ -f "$file" ] || { echo "no $file to back up" >&2; exit 1; }
	# A document is an item, so `op item get` answers "does it exist" without
	# downloading it. Editing keeps one item per machine instead of piling copies.
	if op item get "$title" >/dev/null 2>&1; then
		op document edit "$title" "$file"
		echo "updated 1Password item: $title"
	else
		op document create "$file" --title "$title" --tags ssh,dotfiles >/dev/null
		echo "created 1Password item: $title"
	fi
	;;
restore)
	# Overwriting ~/.ssh/config is the point, but confirm it when a config is
	# already there and someone is watching — a mistyped `restore` for `backup`
	# would otherwise clobber the live file. Non-interactive (CI, a pipe) skips it.
	if [ -t 0 ] && [ -f "$file" ]; then
		printf 'overwrite %s? [y/N] ' "$file"
		read -r reply || reply=
		case "$reply" in y | Y) ;; *) echo "aborted"; exit 0 ;; esac
	fi
	umask 077
	op document get "$title" --out-file "$file"
	chmod 600 "$file"
	echo "restored $file from 1Password item: $title"
	;;
*)
	echo "usage: config-1password.sh backup | restore" >&2
	exit 2
	;;
esac
