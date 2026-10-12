# Text to paste

**No blockquote in a reply, ever. Anything I am meant to copy somewhere else
goes in a fenced code block.** A draft comment, an issue body, a reply to a
client, an email, a PR description, a chat message.

A blockquote renders in the terminal with a bar or `> ` on every line, and that
comes along with the copy, so every line has to be cleaned by hand before it
can be pasted. A code block copies clean and keeps the Markdown inside it
(links, lists, `@mentions`) for the place it lands to render. A quotation that
is not meant for pasting goes inline, in quotation marks.

- One block per thing to paste, tagged `markdown` when it holds Markdown; a
  draft that holds a code block itself gets a longer fence (` ```` `).
- Commentary about the draft goes outside the block, never inside it.
- Links inside are full URLs; see [linking to work](linking-work.md).

In Claude Code, a MessageDisplay hook (`bin/agents/quote-to-fence.py`) shows a
blockquote that slipped through as a code block, so it copies clean anyway. It
changes only the screen, never what the model wrote, so the rule still holds.
