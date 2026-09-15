#!/usr/bin/env bash
# The Omarchy shell plugins this install runs, as a list that can be run rather
# than a README that has to be followed. Run by `make plugins`, after `make stow`
# — landsman.power is stowed files, and enabling it before they are linked fails.
#
# Each plugin from git is pinned to a commit. A plugin is unsandboxed code inside
# the long-lived omarchy-shell process, and a patch in ./patches/ is made against
# one commit — so upstream moves when the SHA here is bumped, not whenever
# `omarchy plugin update` is run. Bumping it and re-running this is the update:
# the patch is taken off, the new commit checked out, the patch put back on.
#
# Idempotent, and quiet when there is nothing to do: a plugin already at its
# commit, already patched, already enabled and already set is left alone, and
# the shell is restarted only when something changed — a plugin reload alone
# has been seen to keep a patched widget's old label.
#
#   bash os/arch/install-plugins.sh

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
: "${PLUGINS_DIR:=$HOME/.config/omarchy/plugins}"
: "${PATCHES_DIR:=$HERE/patches}"
: "${SHELL_CONFIG:=$HOME/.config/omarchy/shell.json}"
CHANGED=0

enabled() {  # enabled <id>
	omarchy plugin list --json | jq -e --arg id "$1" 'any(.[]; .id == $id and .enabled)' >/dev/null
}

git_plugin() {  # git_plugin <id> <git-url> <full commit sha>
	local id=$1 url=$2 commit=$3
	local dir=$PLUGINS_DIR/$id patch=$PATCHES_DIR/$id.patch

	if [ ! -d "$dir" ]; then
		echo "==> Adding $id"
		omarchy plugin add "$url" --yes
		CHANGED=1
	fi

	if [ "$(git -C "$dir" rev-parse HEAD)" != "$commit" ]; then
		echo "==> Pinning $id to ${commit:0:7}"
		if [ -f "$patch" ] && git -C "$dir" apply --reverse --check "$patch" 2>/dev/null; then
			git -C "$dir" apply --reverse "$patch"
		fi
		# Anything still modified is not ours to throw away.
		git -C "$dir" diff --quiet HEAD \
			|| { echo "$id: $dir has local changes that are not $patch - left alone" >&2; exit 1; }
		git -C "$dir" cat-file -e "$commit^{commit}" 2>/dev/null || git -C "$dir" fetch -q origin "$commit"
		git -C "$dir" checkout -q --detach "$commit"
		omarchy plugin validate "$dir" >/dev/null
		CHANGED=1
	fi

	# Reverse-applies cleanly means it is already on. A patch that neither
	# reverses nor applies fails here, loudly, rather than half-applying.
	if [ -f "$patch" ] && ! git -C "$dir" apply --reverse --check "$patch" 2>/dev/null; then
		echo "==> Patching $id"
		git -C "$dir" apply "$patch"
		CHANGED=1
	fi
}

enable() {  # enable <id> [placement...] — the placement is used only the first time
	enabled "$1" && return 0
	echo "==> Enabling $1"
	omarchy plugin enable "$@"
	CHANGED=1
}

disable() {  # disable <id>
	enabled "$1" || return 0
	echo "==> Disabling $1"
	omarchy plugin disable "$1"
	CHANGED=1
}

setting() {  # setting <id> <key> <string value>
	jq -e --arg id "$1" --arg k "$2" --arg v "$3" \
		'any(.bar.layout[]?[]?; .id == $id and .[$k] == $v)' "$SHELL_CONFIG" >/dev/null 2>&1 && return 0
	echo "==> Setting $2 on $1"
	omarchy bar set "$1" "$2" "$3"
	CHANGED=1
}

# Sourced by ./install-plugins.test.sh for the functions above, without the list.
[ "${BASH_SOURCE[0]}" = "$0" ] || return 0

[ "$(uname -s)" = Linux ] && command -v omarchy >/dev/null \
	|| { echo "not an Omarchy install - skipped"; exit 0; }

# Picks up plugins stow linked in since the shell started.
omarchy-shell shell rescanPlugins >/dev/null

# == the list

# The power panel, cloned and patched to count both T480 batteries. Stowed from
# .config/omarchy/plugins/, not cloned — see README.md.
enable landsman.power --after omarchy.monitor
disable omarchy.power

# CPU, memory and temperature in the bar, every 2 s.
git_plugin kb.system-pulse https://github.com/KabirBhattarai/omarchy-system-pulse d12eb182b9f41a58c1d581856f94d593ba5d9888
enable kb.system-pulse --after omarchy.tray
setting kb.system-pulse separator ' · '

# == end of the list

if [ "$CHANGED" -eq 1 ]; then
	echo "==> Restarting the shell"
	omarchy restart shell
else
	echo "plugins: nothing to do"
fi
