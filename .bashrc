# Fragment, not a replacement for the distro ~/.bashrc — `make shell` appends
# this loader to it. Aliases are split across stow packages, so this sources a
# drop-in directory instead of a single file:
#   shared/.config/bash_aliases.d/00-general.sh   portable
#   t480/.config/bash_aliases.d/10-t480.sh        this machine only
for f in ~/.config/bash_aliases.d/*.sh; do
	[ -r "$f" ] && . "$f"
done
unset f
