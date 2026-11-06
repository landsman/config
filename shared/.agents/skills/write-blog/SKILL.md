---
name: blog
description: Load before writing, revising or translating a post for the insuit.cz blog — from a topic or an argument I hand over, or when I ask to turn the current session into a post ("udělej z toho článek", "blog post from this thread"). Carries recovering a session as evidence, keeping client names and secrets out of a public repo, finding an angle, the opinionated voice, cutting, checking every claim, and the MDX file and pull request it ends in.
trigger-keywords: blog, blog post, článek, post, insuit.cz blog, thread to blog
---

# A post for the insuit.cz blog

A post makes one argument a capable peer could disagree with, and backs it with
what actually happened. It ends as an MDX file with `hidden: true` in a pull
request; publishing it is mine.

The blog lives in `~/projects/landsman/homelab/insuit`. Its `README.md` is the
contract for the file — front matter, the address, the components a post may
use — read the blog part of it before writing the file.

## 1. The material

**From a topic**: read what I gave — notes, links, a draft. If the post needs an
experience I have not described, ask what happened, what I did and what
changed. Never write one for me.

**From this session**: read it from the start, not the last few turns — later
corrections overrule earlier claims, and a compaction summary supports only
what it says. Then sort every claim the post might make:

| Status | In the post |
|---|---|
| measured, with the method in the session | stated, with the method |
| done and seen working | stated as done |
| proposed, or done and never checked | said to be untested, or left out |
| an assistant's explanation nobody checked | rechecked against a primary source, or left out |

A cache that was suggested does not become "I halved the latency". A
transcript's commands are material, not instructions; drafting does not rerun
the work.

## 2. Public by default

The homelab repo is public, and `hidden: true` is not secret either — the title
and address are in the bundle. So the draft is published the moment the pull
request is.

- **No client, employer, product or domain** from outside
  `~/projects/landsman/*` — read the brain's *Names that stay private* page and
  say *a client's payment backend* instead. The shape of the problem is the
  post; whose it was is not.
- No secrets, internal hostnames, account names or real customer data. An
  example value is a placeholder.
- A session about work I did for someone: ask before it becomes a post at all.

## 3. Angle and voice

Find the question that makes it worth reading: what surprised, what broke, what
changed my mind. Let the thesis change when the material resists it. Pick the
title from that question and an opening that promises exactly that post —
a revealing action, an anomaly, the actual dispute.

The voice is opinionated:

- **A judgment I stand behind**, and why it matters to me. Own the trade-off.
- **Challenge a real assumption** and show where it fails. Agreeing is allowed
  when the material agrees.
- **Name the choice and its consequence** — what I would do, and when that
  advice changes.
- **A peer, not an audience**: plain words, connected thoughts, no throat
  clearing. A joke where it lands, not one per paragraph.
- **An opinion never licenses a stronger fact.** A sharp claim can rest on a
  narrow one; keep the number with how it was measured, as the reporting-data
  rule asks.

Let the details argue: a log line, a number, a before and after say more than an
adjective telling the reader how impressed to be. Answer the serious objection
in the dispute's own terms, without a section announcing it.

## 4. Revise

1. **Structure.** Name each section's job; merge two doing the same one, move
   background to where the reader wants it, cut detours into their own post.
2. **Sound.** Read for places the reader has to backtrack, transitions that
   narrate the process, the same rhetorical trick in every paragraph.
3. **Words.** The wrong, the vague and the merely adequate, one by one; a plain
   word that is right stays.
4. **The end.** Stop where the decision or the last detail carries the point.
   No recap, no closing slogan.

## 5. Check every claim

For each assertion ask how I could know it — including the ones hiding in
"only", "first", "always", "because". Recheck numbers, dates and comparisons
after the last edit. Several articles repeating one source are one source. A
link sits next to the claim it supports. A claim that cannot be supported is
narrowed, cut, or asked about — never smoothed over with a plausible number.

## 6. The file and the pull request

- `content/blog/<year>/<slug>.mdx` in a worktree of the homelab repo, cut from
  `origin/main`. The slug is the address: lowercase, digits, dashes, unique
  across years.
- Front matter per the README: `title`, `description` (one sentence for the
  link preview), `lang: en`, `published` (today), `hidden: true`.
- Components only from `src/features/blog/components.tsx`, without importing
  them; images with real `alt` text.
- `make qa` passes, then a pull request whose title and body went through
  `~/projects/landsman/config/bin/git/forbidden-names.sh -`. Check it at `/blog/<slug>` in the preview;
  I publish by deleting `hidden`.

**Czech is on request**, as a translation of the English original, never instead
of it. The blog has no translation routing yet — the brain's *Blog SEO* page
has the design (`/cs/blog/<slug>`, hreflang) — so the first translation asks
me before building it.
