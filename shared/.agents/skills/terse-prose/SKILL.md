---
name: terse-prose
description: Load before writing a code comment, a config comment, a PR or MR description, an issue, an error message, release notes, or a reply that explains a change. Carries how to cut an explanation down to its core so it is shorter and explains more.
trigger-keywords: comment*, komentář*, PR description, PR body, popis PR, error message, hlášk*, release notes
---

# Short, and explains more

Shorter is not the goal. **Clearer is, and it is almost always shorter.** A long
explanation usually means the core was never found, so everything got written
down in case it mattered.

## Find the core first

Before writing, say it in one sentence: **what was wrong, and why the fix is
right.** If that sentence does not come, the problem is not understood yet —
more words will not fix it.

Then add only what a reader would otherwise have to ask. The question a reviewer
will ask goes *in*. ("Where does the host come from now?" was the one question
the PR below had to answer, and it was the one it left out.)

## Cut

- **The story.** How it was found, what was tried, what the tool said. The reader
  needs the conclusion.
- **What the diff already shows.** File lists, "changed X to Y", test names.
- **Hedging and throat-clearing.** "Note that", "it is worth mentioning", "this
  ensures that".
- **Sections with one line in them.** A PR is not a form. Headings only when there
  are three or more real parts.
- **What was not done**, unless a reviewer would otherwise ask for it. Then one line.
- **Mannered phrasing.** A metaphor where a plain statement exists: "a dial worth
  turning" for "a parameter worth varying", "earns its keep" for "is still
  needed", "the beating heart of", "hums along". It makes the reader decode what
  the writer could have said, and drags in meanings nobody chose.

## Code comments

Why, not what. One to three lines. The fact that is not visible in the code and
would cost the next person an afternoon — and nothing else.

    # bad, 9 lines
    # Off. The valve would otherwise take the host and port from X-Forwarded-Host /
    # -Port, which Cloudflare passes through from the client untouched, and every
    # redirect is absolute — so `curl -H 'X-Forwarded-Host: example.com'` got a login
    # redirect to example.com. The host comes from Host instead: Cloudflare routes on
    # it and the tunnel answers only app.example.com (infra/cloudflare/tunnel.tf), so
    # a forged one never arrives. An empty name is how Tomcat's RemoteIpValve reads
    # "no header": no request carries a header without a name. Re-enable only ...

    # good, 3 lines
    # Off: the client sets these and Cloudflare passes them through, so anyone could
    # pick the host of our redirects. Host is trustworthy instead — Cloudflare routes
    # on it and the tunnel serves one hostname. "" means "read no header".

## PR descriptions

Problem, with the proof. Fix, and why it is right. How it was verified. Usually
that is three short paragraphs and no headings.

    Closes #454

    Tomcat took the host and port of every redirect from X-Forwarded-Host/-Port.
    The client sets those and Cloudflare passes them through:

        curl -sI -H 'X-Forwarded-Host: evil.com' https://app/  →  location: https://evil.com/login

    Both are ignored now. The host comes from Host, which cannot be forged here:
    Cloudflare routes on it and the tunnel serves one hostname.

    The test binds the prod config the way Boot does and runs the real valve; it
    fails on the old config.

**When deploying it is not just a deploy**, add how to release: migrations and
their order, a config value or secret to set first, a flag, the order across
services, what to watch afterwards, how to roll back. That is the part a reviewer
cannot see in the diff and the one that goes wrong at 5 pm. A plain deploy gets
no such line.

The version that shipped first had five headings, a bullet list of the test's
internals and a section on what was skipped — and still did not say where the
host comes from.

## Error messages

What happened, and what the reader can do next — "The file is larger than 10 MB.
Choose a smaller one", not "Upload failed". No blame words (invalid, illegal,
wrong), no humour, no exclamation mark, and keep what the user typed so they can
fix it rather than retype it. The text goes through a localisation key — see the
localisation rule.

## Release notes

For the people upgrading, never a dump of commit subjects. Breaking changes
first, each with what breaks and the steps to migrate; then the rest grouped as
Added, Changed, Deprecated, Removed, Fixed, Security. Newest version on top, an
ISO date beside it.

## Check before sending

Read it once as the reviewer. Delete every sentence they would not miss. If the
one question they would ask is not answered, add that sentence.
