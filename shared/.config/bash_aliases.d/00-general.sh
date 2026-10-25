# Portable aliases — safe on any machine.

# internet speed test
alias speed='cloudflare-speed-cli'
alias fast='speed'

# eza over ls, with icons (a Nerd Font); `ls -l` adds a git column. Not long by
# default, so a bare `ls` stays a short listing. Plain ls where eza is missing.
if command -v eza >/dev/null; then
	alias ls='eza --icons --git --group-directories-first'
	alias tree='eza --tree --icons'
fi
