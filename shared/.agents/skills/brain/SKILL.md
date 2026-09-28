---
name: brain
description: Load before writing to or reading from my long-term knowledge base in `~/projects/landsman/brain` — after finishing any research (web search, comparing tools, reading docs, an investigation whose findings outlive the session), when I say "remember this", "save it to the brain", "what do I know about X", or ask to tidy the brain up. Carries the ingest, query and lint steps and how to commit from another repo.
---

# Brain

`~/projects/landsman/brain` is my long-term memory, laid out as Karpathy's LLM
Wiki: `raw/` sources that are never edited, `wiki/` pages compiled from them,
`wiki/index.md` as the catalogue, `log.md` as the append-only history.

**Before writing, run `bin/wt.sh start` and read `AGENTS.md` from the
worktree it prints** — not from the main checkout, which may be behind. It is
the schema — file names, frontmatter, and the exact steps of each operation.
This skill says when to run one and how to do it from inside another repo; it
does not repeat the schema.

## Which operation

| Situation | Operation |
|-----------|-----------|
| A research just finished, or I hand over an article, a finding, a note | **ingest** |
| "Remember this" / "save it to the brain" | **ingest** — the thing to remember is the source |
| A question the brain might already answer, including before starting a research | **query** |
| "Tidy up the brain", or a query hit a contradiction | **lint** |

Research counts as finished when its conclusion is given to me. Ingest it then,
in the same turn, without being asked — a finding that stays in the transcript
is gone by the next session. Skip only what is tied to one repo's code and
already lives there, or what I said not to keep.

## Writing: always in a worktree of your own

Other agents write to the brain at the same time. **Never edit or commit in
`~/projects/landsman/brain` itself** — `git add -A` there sweeps another
agent's half-written pages into your commit, and a pull refuses to run over
its changes. Every write goes through a worktree of its own:

    ~/projects/landsman/brain/bin/wt.sh start
    # prints a path — read and write only inside it, per AGENTS.md
    ~/projects/landsman/brain/bin/wt.sh finish <that path> "docs: <what was learned>"

**Use the printed path literally** in every later command and file write — a
shell variable does not survive between tool calls. `start` makes a fresh
worktree on `origin/main`; read the pages there too, the main checkout may be
behind. `finish` commits, rebases until the push goes through, removes the
worktree and updates the main checkout. On a conflict it stops and names the
files: edit them keeping both sides' facts, remove the markers, and run
`finish` again — it continues the rebase itself. On any other failure it
leaves the worktree with the unpushed commit in it; do not delete it, tell me.

Pushes go straight to `main`: the brain's AGENTS.md waives the branch-and-PR
rule for that repo only. Reading for a query needs no worktree — the main
checkout is fine for that.

## What goes into raw/

What was found, not the conversation that found it: the question, the
findings, the decision if one was made, and **every URL a finding came from**.
Numbers keep the method they were measured with. A wiki page is only as
checkable as the raw file behind it.

## What goes into wiki/

Everything a reader needs **without opening `raw/`** — agents read the wiki,
not the evidence behind it. The reasoning behind a decision, and a link next
to every tool, project or claim, not just its name. If the finding was also
given to me as an answer, the page holds at least what that answer said:
compiling means organising, not shortening.

## Then tell me

One line at the end of the answer: which pages were created or updated. Not
the diff.
