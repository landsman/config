#!/usr/bin/env bash
# Self-check for ./claude-mentions.sh, with gh stubbed. What it would get wrong
# silently: replacing the allowlist, so the repo's own CI stops starting next;
# widening a repo that was never on "selected"; or a PUT on every run.
set -eu

script="$(cd "$(dirname "$0")" && pwd)/claude-mentions.sh"
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fails=0

check() { # check <behaviour> <command...>
  local name=$1; shift
  if "$@"; then echo "ok   $name"; else echo "FAIL $name"; fails=$((fails + 1)); fi
}

mkdir "$t/bin"
cat >"$t/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"--jq .allowed_actions"*) echo "$POLICY" ;;
  *"-X PUT"*) { echo "PUT $*"; cat; } >>"$LOG" ;;
  *selected-actions*) echo "$SELECTED" ;;
  *secrets*) echo "$SECRETS" ;;
esac
EOF
chmod +x "$t/bin/gh"
export PATH="$t/bin:$PATH" LOG="$t/log" SECRETS=CLAUDE_CODE_OAUTH_TOKEN

run() { # run <policy> <selected-json> [args...]
  POLICY=$1 SELECTED=$2; shift 2
  : >"$LOG"
  POLICY=$POLICY SELECTED=$SELECTED "$script" "$@" >"$t/out" 2>&1
}

mise='{"github_owned_allowed":true,"verified_allowed":false,"patterns_allowed":["jdx/mise-action@*"]}'
done_='{"github_owned_allowed":true,"verified_allowed":false,"patterns_allowed":["jdx/mise-action@*","anthropics/claude-code-action@*","oven-sh/setup-bun@*"]}'

patterns() { [ "$(jq -c "$1" <<<"$body")" = "$2" ]; }
no_put() { ! grep -q '^PUT' "$LOG"; }
one_put_keeping_mise() { [ "$(grep -c '^PUT' "$LOG")" = 1 ] && grep -q 'jdx/mise-action' "$LOG"; }
refused() { ! run local_only '' landsman/x && no_put; }
token_reported() { grep -q 'no CLAUDE_CODE_OAUTH_TOKEN' "$t/out"; }

body=$("$script" allowlist "$mise")
check "the allowlist keeps what was there and appends both actions" \
  patterns .patterns_allowed '["jdx/mise-action@*","anthropics/claude-code-action@*","oven-sh/setup-bun@*"]'
check "the two flags are carried over unchanged" patterns '[.github_owned_allowed, .verified_allowed]' '[true,false]'
body=$("$script" allowlist "$done_")
check "nothing to PUT once both are allowed" [ -z "$body" ]

run selected "$mise" landsman/x
check "a selected repo gets one PUT that still lists its own actions" one_put_keeping_mise
run selected "$done_" landsman/x
check "a second run changes nothing" no_put
run all '' landsman/x
check "a repo that allows all is not narrowed" no_put
check "any other policy is refused" refused
run selected "$mise" --dry-run landsman/x
check "--dry-run changes nothing" no_put
SECRETS='' run all '' landsman/x
check "a missing token is reported" token_reported

[ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
