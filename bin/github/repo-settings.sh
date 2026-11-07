#!/usr/bin/env bash
# Applies the repository settings on GitHub that no file in a repo can express,
# and that the Terraform provider cannot set yet either.
#
#   repo-settings.sh [--dry-run] <owner/repo>...
#   repo-settings.sh [--dry-run] --all <owner>   every non-archived, non-fork repo
#
# Dependabot alerts list a known vulnerability in a dependency, whether or not anything
# in CI reads the lockfile. Security updates open the pull request that fixes
# it, and skip the cooldown dependabot.yml sets for version updates — a CVE is
# the case the cooldown is not for. Both are free, private repos included.
#
# A pull request from someone's first contribution waits for an admin to
# approve it before any workflow runs, so a stranger cannot spend the runner
# minutes or try the workflows out. GitHub's default only holds accounts that
# are new to GitHub. all_external_contributors would hold every outsider's PR.
#
# Safe to run again: each call sets the state, it does not toggle it. Needs a
# gh login with admin on the repositories.
set -euo pipefail

dry=
if [ "${1:-}" = --dry-run ]; then dry=1; shift; fi

if [ "${1:-}" = --all ]; then
  owner=${2:?usage: --all <owner>}
  repos=()
  # A read loop rather than mapfile, which the bash 3.2 on macOS does not have.
  while IFS= read -r r; do repos+=("$r"); done < <(gh repo list "$owner" --no-archived --source --limit 1000 --json nameWithOwner --jq '.[].nameWithOwner')
else
  [ $# -gt 0 ] || { sed -n '2,6p' "$0" >&2; exit 2; }
  repos=("$@")
fi

for repo in "${repos[@]}"; do
  for setting in vulnerability-alerts automated-security-fixes; do
    if [ -n "$dry" ]; then
      echo "would enable $setting on $repo"
    else
      gh api --silent -X PUT "repos/$repo/$setting"
      echo "enabled $setting on $repo"
    fi
  done
  if [ -n "$dry" ]; then
    echo "would require approval for first-time contributors on $repo"
  else
    gh api --silent -X PUT "repos/$repo/actions/permissions/fork-pr-contributor-approval" -f approval_policy=first_time_contributors
    echo "required approval for first-time contributors on $repo"
  fi
done
