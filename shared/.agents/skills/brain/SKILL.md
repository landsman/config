---
name: brain
description: Load before writing to or reading from my long-term knowledge base in `~/projects/landsman/brain` — after finishing any research (web search, comparing tools, reading docs, an investigation whose findings outlive the session), when I say "remember this", "save it to the brain", "what do I know about X", or ask to tidy the brain up. Carries the ingest, query and lint steps and how to commit from another repo.
---

# Brain

`~/projects/landsman/brain` is my long-term memory, laid out as Karpathy's LLM
Wiki: `raw/` sources that are never edited, `wiki/` pages compiled from them,
`wiki/index.md` as the catalogue, `log.md` as the append-only history.

**Read `~/projects/landsman/brain/AGENTS.md` before writing anything there.** It
is the schema — file names, frontmatter, and the exact steps of each operation.
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

## From another repo

The brain is its own git repo, so every command runs against it, not the
current working directory:

    git -C ~/projects/landsman/brain pull --rebase
    # … write raw/, wiki/, index, log per AGENTS.md …
    git -C ~/projects/landsman/brain add -A
    git -C ~/projects/landsman/brain commit -m "docs: <what was learned>"
    git -C ~/projects/landsman/brain push

Straight to `main`: the brain's own AGENTS.md waives the branch-and-PR rule
for that repo only. Pull before writing, not just before pushing — another
machine or agent may have touched the same page.

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
