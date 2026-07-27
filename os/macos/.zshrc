# macOS shell. Symlinked here by `make stow` — edit it in the repo, not in $HOME.

# Homebrew. `make brew` installs it; without this line its PATH lives only in
# whatever rc the installer patched, which is not tracked here.
[ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv zsh)"

export PATH="$HOME/.local/bin:/opt/homebrew/opt/libpq/bin:$PATH"
export PATH="$PATH:$HOME/.lmstudio/bin"          # LM Studio CLI (lms)
export PATH="$PATH:$HOME/Library/Application Support/JetBrains/Toolbox/scripts"

# Completion. zsh ships `_make`, so `make <TAB>` already lists the targets of the
# Makefile in $PWD — no plugin needed. `menu select` is what makes that list
# arrow-navigable, the bit the JetBrains terminal has and a bare zsh doesn't.
fpath=("$HOME/.docker/completions" $fpath)       # Docker Desktop completions
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'   # case-insensitive

# Same drop-in directory the .bashrc fragment loads, so aliases work in both
# shells. (N) is the zsh way to say "no matches is fine" — without it an empty
# directory makes every new shell start with an error.
for f in ~/.config/bash_aliases.d/*.sh(N); do
	[ -r "$f" ] && . "$f"
done
unset f

eval "$(mise activate zsh)"
