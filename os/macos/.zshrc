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
#
# Only a completion Homebrew did not install needs a line here. `brew shellenv`
# above already puts $HOMEBREW_PREFIX/share/zsh/site-functions on fpath, so
# everything in the Brewfile completes with nothing added — worth writing down,
# because several of those CLIs print a setup recipe that assumes you generated
# the file by hand. `stripe completion` is the one that came up: it asks for a
# ~/.stripe on fpath and a compinit of its own, and following it would add a
# directory duplicating the formula's own _stripe plus a second compinit for
# zsh-autocomplete to fight. Docker Desktop is not a brew install, which is why
# it is the one that does get a line.
fpath=("$HOME/.docker/completions" $fpath)       # Docker Desktop completions
ac="$HOMEBREW_PREFIX/share/zsh-autocomplete/zsh-autocomplete.plugin.zsh"
if [ -r "$ac" ]; then source "$ac"; else autoload -Uz compinit && compinit; fi
unset ac

# television: Ctrl-T for context-aware completion, Ctrl-O for its history picker.
# Both keys come from shared/.config/television/config.toml.
command -v tv >/dev/null && eval "$(tv init zsh)"

# hstr owns Ctrl-R, ahead of both zsh-autocomplete's history menu and television.
# Has to come after the source above, because the last bindkey wins. The widget
# body is upstream's `hstr --show-zsh-configuration`: Darwin has no TIOCSTI, so
# the line cannot be pushed back into the input buffer and hstr's output is read
# from a subshell instead.
alias hh=hstr
setopt histignorespace           # a leading space keeps a command out of history
export HSTR_CONFIG=hicolor
export HSTR_TIOCSTI=n
hstr_no_tiocsti() {
	zle -I
	{ HSTR_OUT="$( { </dev/tty hstr -- ${BUFFER}; } 2>&1 1>&3 3>&- )"; } 3>&1
	BUFFER="${HSTR_OUT}"
	CURSOR=${#BUFFER}
	zle redisplay
}
zle -N hstr_no_tiocsti
bindkey '^R' hstr_no_tiocsti

# Same drop-in directory the .bashrc fragment loads, so aliases work in both
# shells. (N) is the zsh way to say "no matches is fine" — without it an empty
# directory makes every new shell start with an error.
for f in ~/.config/bash_aliases.d/*.sh(N); do
	[ -r "$f" ] && . "$f"
done
unset f

# ssh-agent. macOS launches one per login session and it comes up empty — the
# passphrases are in the login Keychain, but nothing has loaded them from there
# since Monterey dropped that half. Nothing notices until the first commit of
# the day: signing is SSH (`make git`), `ssh-keygen -Y sign` asks the agent for
# the key, and an empty agent sends it back to the key file to prompt — from a
# GUI git client, with nowhere to type. Guarded on the agent already holding
# keys, so the usual shell pays one fork and not a Keychain round trip.
ssh-add -l >/dev/null 2>&1 || ssh-add --apple-load-keychain 2>/dev/null

eval "$(mise activate zsh)"

# Qwen Code PATH block begin
export PATH='/Users/landsman/.local/bin':$PATH
# Qwen Code PATH block end
