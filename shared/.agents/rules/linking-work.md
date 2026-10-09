# Linking to a PR, an MR, an issue or a CI run

Whenever one is mentioned, give the **full URL**, not the number.

    ✅ Fixed in https://github.com/owner/repo/pull/177
    ❌ Fixed in #177
    ❌ Fixed in PR 177

`#177` is not clickable, and in a terminal there is nothing to resolve it against —
it means opening a browser, finding the right repository, and typing the number.
The URL is already in hand: whatever created the PR printed it, and `gh pr view
<n> --json url -q .url` recovers one that scrolled away.

The same applies to an issue, a workflow run, and a comparison — anything with an
address. A number is a lookup task handed back to the reader.

Alongside the URL, keep whatever makes it readable: `#177` next to the link, or
the title. The rule is that the link is present, not that nothing else is.

## Where this does **not** apply

**Inside the repository.** A commit message, a PR body, an issue comment or a doc
in the repo refers to a sibling PR as `#177`, because the forge resolves it there
and a full URL is noise that breaks when a repo moves.

That exception is for **the same repository on the same forge**, and nothing
wider. Anything written in one repo about work in another — above all on another
forge, such as a Forgejo issue about a GitHub PR — takes the full URL. Short forms
resolve against the forge they are written on: `owner/repo#33` in a Forgejo issue
points at a Forgejo repository of that name, which may not exist or may be a
mirror, so the link silently leads somewhere else.

    ✅ in a Forgejo issue: https://github.com/landsman/homelab/pull/33
    ❌ in a Forgejo issue: landsman/homelab#33

That is also the line the confidentiality rule draws — see
[where the repos live](where-repos-live.md). A URL carries the owner and the repo
name, which is fine in a terminal I am reading and not fine in anything that
leaves the machine. Linking to a client PR in conversation is expected; putting
that URL in a public doc or a commit message is the thing that rule forbids.

## Reading one I handed you

A link to my own work is behind a login: read it with the signed-in tool its
skill names (`forgejo` for git.insuit.cz, `gh` for GitHub), never `WebFetch` or
an anonymous `curl`. A missing server is a finding to report, not a reason to
scrape the page.
