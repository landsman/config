# Portable aliases — safe on any machine.

# internet speed test
alias speed='cloudflare-speed-cli'
alias fast='speed'

# eza over ls, with icons (a Nerd Font) and a git column; plain ls without it
if command -v eza >/dev/null; then
	alias ls='eza --icons --git --group-directories-first'
	alias tree='eza --tree --icons'
fi
