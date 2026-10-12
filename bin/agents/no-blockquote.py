#!/usr/bin/env python3
"""Stop hook: a reply that holds a Markdown blockquote is sent back to be rewritten.

A blockquote renders in the terminal with a bar or `> ` on every line, and the
copy takes it along, so a draft meant for pasting has to be cleaned line by
line. The rule (text-to-paste.md) says to use a fenced code block; this is the
part that does not depend on the rule being remembered.

Only the final reply is checked, as Claude Code passes it in
`last_assistant_message`; the transcript is not read, because the docs do not
promise the final message is in it yet at Stop time. Lines inside a fenced
block are content and skipped. When the hook already blocked once
(`stop_hook_active`), it lets the reply through rather than loop.
"""
from __future__ import annotations

import json
import re
import sys

QUOTE = re.compile(r"^ {0,3}>")
FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})(.*)$")


def has_blockquote(text: str) -> bool:
    fence = None  # the opener's run of ` or ~, while inside a block
    for line in text.splitlines():
        m = FENCE.match(line)
        if fence is None:
            if m and not (m.group(1)[0] == "`" and "`" in m.group(2)):
                fence = m.group(1)
            elif QUOTE.match(line):
                return True
        # CommonMark: the closer is the same character, at least as long, with nothing after it.
        elif m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence) and not m.group(2).strip():
            fence = None
    return False


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError:
        return
    if data.get("stop_hook_active"):
        return
    if has_blockquote(data.get("last_assistant_message") or ""):
        print(json.dumps({
            "decision": "block",
            "reason": "The reply uses a Markdown blockquote (`> `). It copies with a marker on every line. "
                      "Send the reply again with no blockquote: text meant for pasting in a fenced code block "
                      "(tagged markdown when it holds Markdown), a quotation inline; see text-to-paste.md.",
        }))


if __name__ == "__main__":
    main()
