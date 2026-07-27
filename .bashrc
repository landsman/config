# Fragment, not a replacement for the distro ~/.bashrc — `make shell` appends
# this loader to it. Aliases are split across stow packages, so this sources a
# drop-in directory instead of a single file:
#   shared/.config/bash_aliases.d/00-general.sh   portable
#   t480/.config/bash_aliases.d/10-t480.sh        this machine only

# Homebrew on Linux, if `make brew` installed it. Same Brewfile as the Mac, so
# stow and the CLI tooling come from one list on every machine.
[ -x /home/linuxbrew/.linuxbrew/bin/brew ] \
	&& eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

for f in ~/.config/bash_aliases.d/*.sh; do
	[ -r "$f" ] && . "$f"
done
unset f
