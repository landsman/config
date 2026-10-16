---
name: perplexity-research
description: Load before writing a deep-research prompt for Perplexity — picking a new dependency (npm, Gradle or Maven, Composer, Go, PyPI, Homebrew), comparing tools, a market, the state of a standard — and when I hand back what Perplexity returned, a downloaded Markdown file. Carries what the prompt must contain, where to look and what to rank by for a dependency, what must stay out of it, the output contract that makes the result easy to bring back, and how to take it back — read it, check its sources, file it in the brain.
trigger-keywords: perplexity, deep research, rešerš*, průzkum*
---

# Research prompts for Perplexity

I run the research in the Perplexity desktop app and download the result as a
Markdown file. Perplexity sees nothing but the prompt: no disk, no repo, no
earlier conversation, no skill. Everything it needs is in the prompt, and
everything that must not leave the machine is not.

## Writing the prompt

- **Self-contained context.** What is being built, for whom, the stack with
  versions, what is already decided and must not be reopened, and the
  constraints that rule candidates out. Paste the facts, never a path to them.
- **Nothing private.** It is an external service: no client or employer name,
  product name, repo, path, internal host or domain, no code from a client
  repo, no secret. Describe the shape — "a booking app for small service
  businesses". Write the prompt to the scratchpad and check it from the config
  repo, where no client counts as its own:

      (cd ~/projects/landsman/config && bin/git/forbidden-names.sh <prompt file>)

- **The question and the criteria, ranked** — which decide, in what order, and
  which are hard filters.
- **Picking a dependency** — a library, a plugin or a tool for npm, Gradle or Maven,
  Composer, Go, PyPI or Homebrew: paste the sources and the criteria from
  [dependencies.md](dependencies.md) that apply.
- **Candidates to start from**, marked as not exhaustive, plus the baseline:
  doing nothing, or building it ourselves.
- **Method**: a longlist, a filter, then a deep look at the shortlist; each
  rejected candidate keeps a one-line reason.
- **Evidence rules**, from [reporting data](../../rules/reporting-data.md):
  every fact with a full URL and the date it was checked, every number with its
  method, what was verified kept apart from what a vendor claims and from what
  is assumed, and "not found" said instead of guessed.
- **The output contract** below, with the filename filled in.

Hand it over as one fenced block — a four-backtick fence, since the prompt holds
code blocks — with any note on which mode to pick outside it. Then stop.

## The output contract

The end of every prompt, `<slug>` replaced:

    ## Output

    Deliver one downloadable Markdown file named `<slug>.md`, in English. If you
    cannot attach a file, reply with that document and nothing else, so that
    exporting this thread as Markdown yields exactly it.

    - Start with YAML front matter: `title`, `date` (today, ISO 8601),
      `question` (one line).
    - Then the answer: the recommendation or the conclusion, in one paragraph.
    - Tables as GitHub-flavoured Markdown pipe tables, never images.
    - Cite with full URLs inline, next to the claim. Numbered markers alone get
      lost when the thread is exported.
    - End with `## Sources`: every URL used, each with the date it was read.
    - Nothing only in a chart; give the numbers.

## Taking it back

I drag the file into the terminal, which pastes its path.

1. **Read it whole.** It is the source, not a summary of one.
2. **Check what the conclusion rests on.** Open the two or three sources the
   recommendation depends on and confirm they say what is claimed: a research
   tool cites pages that say something else, and a number with no method is a
   claim. Say what you checked and what did not hold.
3. **File it in the brain** (`brain` skill): the file into `raw/` as it arrived,
   the finding compiled into `wiki/`, with what your check found.
4. **Then act on it** — the plan, the issue or the code it was for.
