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

That is also the line the confidentiality rule draws — see
[where the repos live](where-repos-live.md). A URL carries the owner and the repo
name, which is fine in a terminal I am reading and not fine in anything that
leaves the machine. Linking to a client PR in conversation is expected; putting
that URL in a public doc or a commit message is the thing that rule forbids.
