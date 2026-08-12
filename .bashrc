# Fragment, not a replacement for the distro ~/.bashrc — `make shell` adds a
# single `. <repo>/.bashrc` line to it, so edits here reach every machine that
# ran it. Aliases are split across stow packages, so this sources a drop-in
# directory instead of a single file:
#   shared/.config/bash_aliases.d/00-general.sh   portable
#   t480/.config/bash_aliases.d/10-t480.sh        this machine only

# Homebrew on Linux, if `make brew` installed it. Same Brewfile as the Mac, so
# stow and the CLI tooling come from one list on every machine.
[ -x /home/linuxbrew/.linuxbrew/bin/brew ] \
	&& eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

# Where `make apps` puts corepack's yarn shim. Ubuntu's own ~/.profile adds this
# too, but only if the directory already existed at login — which on a machine
# being set up it did not. macOS gets the same line from os/macos/.zshrc.
case ":$PATH:" in
	*":$HOME/.local/bin:"*) ;;
	*) export PATH="$HOME/.local/bin:$PATH" ;;
esac

for f in ~/.config/bash_aliases.d/*.sh; do
	[ -r "$f" ] && . "$f"
done
unset f

# hstr on Ctrl-R, straight from `hstr --show-configuration` on the T480. It is
# the no-TIOCSTI variant there too: modern kernels default dev.tty.legacy_tiocsti
# to 0, so the chosen line cannot be pushed into the input buffer and is read
# back from a subshell instead — same reason as the macOS side in
# os/macos/.zshrc, which also gives hstr Ctrl-R ahead of everything else.
if command -v hstr >/dev/null; then
	alias hh=hstr
	export HSTR_CONFIG=hicolor
	export HSTR_TIOCSTI=n
	shopt -s histappend
	export HISTCONTROL=ignorespace   # a leading space keeps a command out of history
	export HISTFILESIZE=10000        # distro default is 500
	export HISTSIZE=${HISTFILESIZE}
	# keep bash's in-memory history and the file in sync, so hstr sees everything
	export PROMPT_COMMAND="history -a; history -n; ${PROMPT_COMMAND}"
	function hstrnotiocsti {
		{ READLINE_LINE="$( { </dev/tty hstr ${READLINE_LINE}; } 2>&1 1>&3 3>&- )"; } 3>&1
		READLINE_POINT=${#READLINE_LINE}
	}
	# `bind` only works in an interactive shell
	if [[ $- =~ .*i.* ]]; then bind -x '"\C-r": "hstrnotiocsti"'; fi
fi
