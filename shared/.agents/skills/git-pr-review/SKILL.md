---
name: pr-review
description: Load when a pull request or merge request has review comments to deal with — a human's or a bot's (Greptile, CodeRabbit, Copilot) — when I say "PR comments", "review", "připomínky", and before reporting a PR of yours as done. Carries reading every thread, deciding each, fixing, replying in the thread, resolving it, and what goes back to me.
trigger-keywords: review*, komentář*, připomínk*, greptile, coderabbit, resolve*, resolvn*
---

# Review comments on a pull request

**A review is finished when every thread has a reply and the fixed ones are
resolved — not when the fix is pushed.** An open thread reads as unaddressed
work, a bot's included. I should never have to ask for the replies.

## The steps, every time

1. **Read all of it**: inline threads, review bodies and plain PR comments, bots
   included. A bot's summary comment often repeats its threads; answer the
   threads.
2. **Decide each finding on its merits.** Reproduce it or read the code it
   points at. Valid → fix. Not valid → no change, and the reply says why.
   Never fix something silently and never ignore it silently.
3. **Fix in new commits**, one per finding when they are independent, each with
   the check that goes red without it ([shell scripts](../../rules/shell-scripts.md)
   for a `.sh`). Check the PR is still open before pushing
   ([pushing to a PR](../../rules/pushing-to-a-pr.md)).
4. **Reply in each thread** after the push: what changed, the short SHA, how it
   was checked — or why nothing changed. Two or three sentences,
   [terse](../write-terse-prose/SKILL.md), no attribution.
5. **Resolve the thread** when it was fixed. A declined one stays open: that
   disagreement is mine to settle.
6. **Fix the PR body** when the change makes it wrong — it becomes the squash
   commit.
7. **Report to me** one line per thread: fixed / declined and why, with the
   thread's URL. Name any thread you could not resolve.

## GitHub

Threads, with what a reply and a resolve need:

    gh api graphql -f query='{repository(owner:"<o>",name:"<r>"){pullRequest(number:<n>){
      reviewThreads(first:100){nodes{id isResolved comments(first:1){nodes{databaseId path body}}}}}}}'

Plain comments and review bodies: `gh pr view <n> --comments`.

Reply, by the first comment's `databaseId`:

    gh api repos/<o>/<r>/pulls/<n>/comments/<databaseId>/replies -f body='…' --jq .html_url

Resolve, one id per call — in zsh an unquoted `$ids` is one word, not a list:

    gh api graphql -f query='mutation($id:ID!){resolveReviewThread(input:{threadId:$id}){thread{isResolved}}}' -f id=<thread id>

Read the threads again at the end: every fixed one `isResolved: true`.

## Forgejo

Load the [forgejo](../git-forgejo/SKILL.md) skill first: `list_pull_reviews`
and `list_pull_review_comments` read them. If no tool resolves a conversation,
reply anyway and name the thread as left open in the report.

## GitLab

    glab api projects/:id/merge_requests/<n>/discussions
    glab api -X POST projects/:id/merge_requests/<n>/discussions/<d>/notes -f body='…'
    glab api -X PUT  "projects/:id/merge_requests/<n>/discussions/<d>?resolved=true"
