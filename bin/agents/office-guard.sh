#!/usr/bin/env bash
# Claude Code hook: keep a Bash command from overwriting an office document the
# user changed since the agent last touched it.
#
#   office-guard.sh pre    PreToolUse on Bash: back the files up, refuse on a change or a lock file
#   office-guard.sh post   PostToolUse on Bash: remember the files' modification times
#
# The rule (shared/.agents/rules/files-i-edit-too.md) asks the agent to check
# this itself. Edit and Write already refuse a file changed since it was read,
# but a .docx is changed by a script run through Bash, where nothing did — and
# that is how a document was once regenerated over the user's edits.
#
# A refusal records the new time, so the retry passes: the agent is told once,
# then rereads. Every version seen is copied to the backups folder first, kept
# 30 days. The first command on a file in a session is let through, since the
# agent holds no older version of it yet.
#
# ponytail: files are found by name, in the command and in a script it runs. A
# path built at runtime (a glob, a variable, a directory walk) is not seen;
# match on more if an agent routes around it.
set -euo pipefail

exts='docx|xlsx|xlsm|pptx|odt|ods|odp|numbers|pages|rtf|doc|xls|ppt'
mode=${1:?usage: office-guard.sh pre|post}
input=$(cat)
session=$(jq -r '.session_id // ""' <<<"$input")
cwd=$(jq -r '.cwd // "."' <<<"$input")
cmd=$(jq -r '.tool_input.command // ""' <<<"$input")
[ -n "$session" ] || exit 0
tmp=${TMPDIR:-/tmp}
state="${tmp%/}/claude-office-guard-$session"
backups="${XDG_STATE_HOME:-$HOME/.local/state}/agent-backups"

# Paths ending in an office extension: quoted (spaces allowed), escaped, or bare.
mentions() {
  grep -oiE "\"[^\"]*\.($exts)\"|'[^']*\.($exts)'|([^\"' ;|&<>()=]|\\\\ )+\.($exts)" <<<"$1" |
    sed -E "s/^[\"']//; s/[\"']\$//; s/\\\\ / /g" || true
}

absolute() {
  case $1 in
    /*) echo "$1" ;;
    \~/*) echo "$HOME/${1#\~/}" ;;
    *) echo "$cwd/$1" ;;
  esac
}

# Existing documents the command names, directly or inside a script it runs.
documents() {
  {
    mentions "$cmd"
    for s in $(grep -oE "[^\"' ]+\.(py|js|mjs|ts|rb|sh)" <<<"$cmd" || true); do
      s=$(absolute "$s")
      if [ -f "$s" ]; then mentions "$(cat "$s")"; fi
    done
  } | while IFS= read -r f; do
    f=$(absolute "$f")
    if [ -e "$f" ]; then echo "$f"; fi
  done | sort -u
}

key() { cksum <<<"$1" | cut -d' ' -f1; }
mtime() { date -r "$1" +%s; }

# Word and Excel leave ~$name beside an open file (its first characters cut on
# a long name), LibreOffice .~lock.name#.
locked() {
  local dir name l
  dir=$(dirname "$1") name=$(basename "$1")
  [ -e "$dir/.~lock.$name#" ] && return 0
  for l in "$dir"/'~$'*; do
    [ -e "$l" ] && [[ $name == *"${l##*/\~\$}" ]] && return 0
  done
  return 1
}

pre() {
  local f now name b k reasons=""
  mkdir -p "$state" "$backups"
  find "$backups" -type f -mtime +30 -delete 2>/dev/null || true
  while IFS= read -r f; do
    if locked "$f"; then
      reasons+="$f is open in an app (a lock file sits beside it), and what is unsaved there is not on disk. Ask the user to save and close it, then run this again. "
      continue
    fi
    now=$(mtime "$f") name=$(basename "$f") k="$state/$(key "$f")"
    b="$backups/${name%.*}.$now.$(key "$f").${name##*.}"
    [ -e "$b" ] || cp -R "$f" "$b" # not -p: the 30-day prune goes by when the copy was made
    if [ -f "$k" ] && [ "$(cat "$k")" != "$now" ]; then
      reasons+="$f changed since your last command on it: the user edited it. Read it again and apply the change to what is there now, never to the version you remember (rules/files-i-edit-too.md). Every version is backed up in $backups. "
      echo "$now" >"$k"
    fi
  done < <(documents)
  [ -n "$reasons" ] || return 0
  jq -n --arg r "${reasons% }" '{hookSpecificOutput: {hookEventName: "PreToolUse",
    permissionDecision: "deny", permissionDecisionReason: $r}}'
}

post() {
  local f
  mkdir -p "$state"
  while IFS= read -r f; do mtime "$f" >"$state/$(key "$f")"; done < <(documents)
}

case $mode in
  pre) pre ;;
  post) post ;;
  *) echo "usage: office-guard.sh pre|post" >&2 && exit 2 ;;
esac
