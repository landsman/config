---
name: forgejo
description: Load before opening a git.insuit.cz link or touching a pull request, issue, review comment, file or CI run on that Forgejo — before any curl, WebFetch or MCP call to it.
trigger-keywords: git.insuit.cz, forgejo*
---

# Reading git.insuit.cz

`git.insuit.cz` is my Forgejo, and most repos on it are private. **Go straight to
the `forgejo` MCP server** — it is signed in with my token. `curl`, `WebFetch`
and the anonymous `/api/v1` all get a login page or a 404, and WebFetch is
denied outright.

The tools are deferred, so load what the task needs in one call first:

    ToolSearch select:mcp__forgejo__get_pull_request_by_index,mcp__forgejo__list_pull_reviews,mcp__forgejo__list_pull_review_comments,mcp__forgejo__list_issue_comments,mcp__forgejo__get_pull_request_diff

## URL → tool

Every URL is `https://git.insuit.cz/<owner>/<repo>/…`; `owner` and `repo` go
into every call.

| URL tail | Tool |
|----------|------|
| `pulls/<n>` | `get_pull_request_by_index`, `get_pull_request_diff`, `list_pull_request_files` |
| `pulls/<n>`, its review comments | `list_pull_reviews`, then `list_pull_review_comments` per review `id` |
| `pulls/<n>` or `issues/<n>`, the conversation | `list_issue_comments` — a PR's top-level comments live here, not under reviews |
| `issues/<n>` | `get_issue_by_index` |
| `src/{branch,tag,commit}/<ref>/<path>` | `get_file_content` with `ref` and `filePath`; `start_line`/`end_line` for a slice, `#L10-L20` in the URL says which |
| `actions/runs/<n>` | `get_workflow_run`, `list_action_run_jobs`, `get_action_job_logs` per `job_id`; if `<n>` is not the run id, `list_workflow_runs` finds it |

**Comments on a PR come from three places**: inline review comments
(`list_pull_review_comments`, one call per review), the review bodies
themselves (`list_pull_reviews`), and the plain conversation
(`list_issue_comments`). Reading only one of them and calling the review handled
is the miss this table exists to prevent.

## Checking it out

The code itself comes over git, not the MCP: the remote is already set up with
credentials, so `git fetch` / `git switch` in the local checkout works. Answering
a comment is `create_issue_comment`; posting a review is `create_pull_review`.

## When the server is missing

No `mcp__forgejo__*` tools in the session means the server did not start:
`FORGEJO_ACCESS_TOKEN` is unset or `forgejo-mcp` is not built. Say so and point
at `make claude` and `make forgejo-mcp` (`.docs-llm/mcp-servers.md` in the config
repo) — do not fall back to scraping the web UI.
