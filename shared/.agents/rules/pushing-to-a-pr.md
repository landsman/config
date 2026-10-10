# Pushing to a pull request

**Before pushing more commits to a branch whose pull request was opened more than
fifteen minutes ago, check that the pull request is still open.** I merge as soon
as a PR looks right, often while an agent is still working on the branch. A push
after that lands on a branch nobody will merge again, and the work is silently not
on the main branch.

How to check depends on the forge the repo lives on, so read it from
`git remote get-url origin` first rather than reaching for `gh` by habit — `gh`
against a Forgejo or Azure DevOps remote fails, and a failed check reads too easily
as "nothing to worry about".

| Remote host | Check | Merged means |
|-------------|-------|--------------|
| `github.com` | `gh pr view <n> --json state,mergedAt` | `"state": "MERGED"` |
| GitLab | `glab mr view <n> -F json \| jq .state` | `"merged"` |
| Forgejo, Gitea | the `forgejo` MCP's `get_pull_request_by_index`, or `curl -s -H "Authorization: token $FORGEJO_ACCESS_TOKEN" "https://<host>/api/v1/repos/<owner>/<repo>/pulls/<n>" \| jq .merged` | `true` |
| `dev.azure.com`, `*.visualstudio.com` | `az repos pr show --id <n> --query status -o tsv` | `completed` |

The words differ too: Azure DevOps calls a merged pull request *completed* and a
closed one *abandoned*, and Forgejo's `state` is only `open` or `closed` — a merged
one is `closed` with `merged: true`, so check `merged`, not `state`. Without the
token a private repository answers 404, and `jq .merged` prints `null`: the
check failed, it did not say the PR is open.

Within the first fifteen minutes, push without checking.

When it is already merged:

- **Do not push to it, and do not edit its title or body** to describe work it
  does not contain. The body is what the squash commit on the main branch says.
- **Carry the rest over to a new branch** cut from the fetched target branch, by
  cherry-picking the commits that came after the merge, and open a new pull request
  that says it follows the merged one.
- **Compare by content, not by ancestry.** A squash merge leaves none of the
  branch's commits in the target's history, so `git merge-base --is-ancestor`
  answers "missing" for all of them. Diff the merge commit against the branch head
  instead, to see what really did not make it.
- **A migration that was merged has shipped.** It may already have run on a real
  database, so the follow-up adds a new one rather than editing it.
