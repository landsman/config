#!/usr/bin/env bash
# Readies a repository for the reusable Claude workflow
# (.github/workflows/claude.yml) — the parts of adopting it that no file in the
# calling repo can express.
#
#   claude-mentions.sh [--dry-run] <owner/repo>...
#   claude-mentions.sh allowlist <selected-actions-json>   the body to PUT, or nothing
#
# A repo whose Actions policy allows only selected actions gets the Claude
# action added to its allowlist. Without it every @claude ends as a
# startup_failure in 0s, with no log and a run page blaming the workflow file.
# The policy is checked against nested actions too, so the setup-bun that
# claude-code-action calls needs its own entry.
#
# It adds to the allowlist, never replaces it: what the repo's own CI needs
# stays. A repo that allows all actions is left alone; one on any other policy
# is refused rather than widened.
#
# The CLAUDE_CODE_OAUTH_TOKEN secret it only checks for. The token comes from
# `claude setup-token` and goes in with
# `gh secret set CLAUDE_CODE_OAUTH_TOKEN -R <owner/repo>`.
#
# Safe to run again. Needs a gh login with admin on the repositories.
set -euo pipefail

needed='["anthropics/claude-code-action@*","oven-sh/setup-bun@*"]'

allowlist() {
  jq -c --argjson need "$needed" '
    (.patterns_allowed // []) as $have
    | ($need - $have) as $missing
    | select($missing != [])
    | {github_owned_allowed, verified_allowed, patterns_allowed: ($have + $missing)}' <<<"$1"
}

if [ "${1:-}" = allowlist ]; then allowlist "${2:?usage: allowlist <json>}"; exit; fi

dry=
if [ "${1:-}" = --dry-run ]; then dry=1; shift; fi
[ $# -gt 0 ] || { sed -n '6,7p' "$0" >&2; exit 2; }

for repo in "$@"; do
  policy=$(gh api "repos/$repo/actions/permissions" --jq .allowed_actions)
  case $policy in
    all) echo "$repo allows all actions, nothing to add" ;;
    selected)
      body=$(allowlist "$(gh api "repos/$repo/actions/permissions/selected-actions")")
      if [ -z "$body" ]; then
        echo "$repo already allows the Claude action"
      elif [ -n "$dry" ]; then
        echo "would set $repo's allowlist to $(jq -c .patterns_allowed <<<"$body")"
      else
        gh api --silent -X PUT "repos/$repo/actions/permissions/selected-actions" --input - <<<"$body"
        echo "allowed the Claude action on $repo"
      fi
      ;;
    *) echo "$repo has Actions policy '$policy', left alone — widen it by hand" >&2; exit 1 ;;
  esac

  gh api "repos/$repo/actions/secrets" --jq '.secrets[].name' | grep -qx CLAUDE_CODE_OAUTH_TOKEN ||
    echo "$repo has no CLAUDE_CODE_OAUTH_TOKEN — gh secret set CLAUDE_CODE_OAUTH_TOKEN -R $repo" >&2
done
