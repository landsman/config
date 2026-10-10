Every rule lives in [`rules/`](rules/), one file each. This file is the index.

A rule there loads unconditionally unless it declares `paths:` frontmatter,
which scopes it to the files it is about. A rule earns that scoping only when
its trigger is a file path *and* breaking it shows up in a diff — GitHub Actions,
Forgejo Actions, Makefiles and writing for agents are the four so far. The rest override a default
I would otherwise fall back to, so they have to be in context before the
mistake, not after.

| Rule | Applies when |
|------|--------------|
| [Where the repos live](rules/where-repos-live.md) | finding a repo on disk, and which ones may be named in public |
| [Reporting data and metrics](rules/reporting-data.md) | a number gets reported — a query, a benchmark, a count |
| [Localisation](rules/localisation.md) | user-facing text gets written — a label, an error, an email |
| [Attribution](rules/attribution.md) | anything leaves the machine or gets committed |
| [Commit messages](rules/commit-messages.md) | writing a commit or a PR title |
| [Short, and explains more](rules/terse-prose.md) | writing a code comment, a PR description, an error message, release notes, an explanation |
| [Linking to work](rules/linking-work.md) | a PR, MR, issue or CI run is mentioned |
| [Git history](rules/git-history.md) | amend, squash, rebase, force-push |
| [Pushing to a pull request](rules/pushing-to-a-pr.md) | pushing to a branch whose PR is older than fifteen minutes |
| [Worktrees](rules/worktrees.md) | an agent is about to change a repo |
| [Subagents](rules/subagents.md) | work is about to be handed to a subagent or run in the background |
| [Everything as code](rules/everything-as-code.md) | a machine, a service or a setting on one of my devices is about to be changed |
| [GitHub Actions](rules/github-actions.md) | writing under `.github/` — scoped; read it before creating one |
| [Forgejo Actions](rules/forgejo-workflows.md) | writing under `.forgejo/workflows/`, or porting a workflow from GitHub — scoped; read it before creating one |
| [Makefiles](rules/makefiles.md) | writing a `Makefile` — scoped; read it before creating one |
| [Writing for agents](rules/writing-for-agents.md) | writing a rule, a skill or a reference an agent loads: a short list, details opened one at a time — scoped; read it before creating one |
| [Shell in a config file](rules/shell-in-config.md) | shell goes inside a YAML or a Makefile |
| [The database is the source of truth](rules/source-of-truth.md) | state is about to live outside the database — memory, a session, a cache, a queue — or two writers race |
| [Brain](rules/brain.md) | researching something, or asked to remember it for later |
| [Browser automation](rules/browser-automation.md) | a web app gets opened to check or drive it |

The folder name is not a preference: `rules/` and `CLAUDE.md` are the only two
things Claude Code loads on its own. A folder named anything else is inert
unless this file imports it with `@`. The rules themselves live one level out,
at `~/.agents/rules/`, shared with every other agent — `rules/` here is a
symlink to them, which the loader follows. After changing the layout, check `/context`
— unconditional rules show up under **Memory files**, and one that quietly
stopped loading looks exactly like one being ignored.
