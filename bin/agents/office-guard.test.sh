#!/usr/bin/env bash
# Self-contained: feeds the hook the JSON Claude Code would, in a throwaway
# folder. What it would get wrong silently: letting a command through after the
# user changed the file, missing a file named only inside a script, skipping
# the backup, or refusing forever instead of once.
set -euo pipefail
hook="$(cd "$(dirname "$0")" && pwd)/office-guard.sh"
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export TMPDIR="$t" HOME="$t" XDG_STATE_HOME="$t/state"
d="$t/docs" && mkdir "$d"
echo v1 >"$d/Smlouva final.docx" && touch -t 202601010000 "$d/Smlouva final.docx" # old: the 30-day prune must spare a fresh copy
echo v1 >"$d/a.xlsx"
printf 'doc = Document("Smlouva final.docx")\n' >"$d/edit.py"

fail=0
run() { # mode command [session] -> hook output
  jq -n --arg c "$2" --arg s "${3-s1}" --arg w "$d" '{session_id: $s, cwd: $w, tool_input: {command: $c}}' |
    bash "$hook" "$1"
}
check() { # expected behaviour command [session]
  out=$(run pre "$3" "${4-s1}")
  got=allow
  if [ -n "$out" ]; then
    jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"$out" >/dev/null && got=deny || got="bad output"
  fi
  if [ "$got" = "$1" ]; then echo "ok   $2"; else echo "FAIL $2 (want $1, got $got)"; fail=1; fi
  run post "$3" "${4-s1}"
}
backups() { find "$t/state/agent-backups" -type f -name "$1" | wc -l | tr -d ' '; }
expect() { # behaviour condition...
  local b=$1; shift
  if "$@"; then echo "ok   $b"; else echo "FAIL $b"; fail=1; fi
}

check allow "the first command on a document passes" "python3 -c 'print(1)' \"Smlouva final.docx\""
expect "the first command backs the document up" [ "$(backups 'Smlouva final.*.docx')" = 1 ]
check allow "an unchanged document passes" "cat 'Smlouva final.docx'"
expect "an unchanged document is not backed up twice" [ "$(backups 'Smlouva final.*.docx')" = 1 ]
echo v2 >"$d/Smlouva final.docx" && touch -t 202602010000 "$d/Smlouva final.docx"
check deny  "a document the user changed is refused" "python3 edit.py"
expect "the changed version is backed up too" [ "$(backups 'Smlouva final.*.docx')" = 2 ]
check allow "the retry after a refusal passes" "python3 edit.py"
check allow "a command naming no document passes" "ls -la"
check allow "an escaped space in a path is understood" "cp Smlouva\\ final.docx /dev/null"
touch -t 202603010000 "$d/Smlouva final.docx"
check deny  "a change is seen through an escaped path" "cp Smlouva\\ final.docx /dev/null"
check allow "another session starts afresh" "cat a.xlsx" s2
touch "$d/~\$a.xlsx"
check deny  "a document open in Excel is refused" "cat a.xlsx" s2
rm "$d/~\$a.xlsx"
touch "$d/.~lock.a.xlsx#"
check deny  "a document open in LibreOffice is refused" "cat a.xlsx" s2
check allow "no session id, nothing to compare against" "cat a.xlsx" ""

exit $fail
