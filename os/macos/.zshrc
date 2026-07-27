# macOS shell. Symlinked here by `make stow` — edit it in the repo, not in $HOME.

# Homebrew. `make brew` installs it; without this line its PATH lives only in
# whatever rc the installer patched, which is not tracked here.
[ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv zsh)"

export PATH="$HOME/.local/bin:/opt/homebrew/opt/libpq/bin:$PATH"
export PATH="$PATH:$HOME/.lmstudio/bin"          # LM Studio CLI (lms)
export PATH="$PATH:$HOME/Library/Application Support/JetBrains/Toolbox/scripts"

# Completion. zsh-autocomplete (in the Brewfile) opens the menu while you type,
# the way the JetBrains terminal does; bare zsh only ever completes on Tab. It
# runs compinit itself and owns the completion zstyles, so there is none of
# either here — see its caveats: `brew info zsh-autocomplete`. fpath has to be
# ready before it is sourced, and the fallback covers a fresh machine where
# `make stow` landed before `make brew`.
fpath=("$HOME/.docker/completions" $fpath)       # Docker Desktop completions
ac="$HOMEBREW_PREFIX/share/zsh-autocomplete/zsh-autocomplete.plugin.zsh"
if [ -r "$ac" ]; then source "$ac"; else autoload -Uz compinit && compinit; fi
unset ac

# Same drop-in directory the .bashrc fragment loads, so aliases work in both
# shells. (N) is the zsh way to say "no matches is fine" — without it an empty
# directory makes every new shell start with an error.
for f in ~/.config/bash_aliases.d/*.sh(N); do
	[ -r "$f" ] && . "$f"
done
unset f

eval "$(mise activate zsh)"
