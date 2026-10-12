#!/usr/bin/env python3
"""Stop hook: a reply that holds a Markdown blockquote is sent back to be rewritten.

A blockquote renders in the terminal with a bar or `> ` on every line, and the
copy takes it along, so a draft meant for pasting has to be cleaned line by
line. The rule (text-to-paste.md) says to use a fenced code block; this is the
part that does not depend on the rule being remembered.

Only the last text the assistant wrote is checked, and lines inside a fenced
block are skipped, since a quoted `> ` there is content. When the hook already
blocked once (`stop_hook_active`), it lets the reply through rather than loop.
"""
import json
import re
import sys

QUOTE = re.compile(r"^ {0,3}>")
FENCE = re.compile(r"^ {0,3}(```|~~~)")


def last_text(transcript: str | None) -> str:
    try:
        with open(transcript, encoding="utf-8") as f:
            lines = f.readlines()
    except (OSError, TypeError):
        return ""
    for line in reversed(lines):
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        if entry.get("type") != "assistant":
            continue
        content = entry.get("message", {}).get("content", [])
        texts = [c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text"]
        if texts:
            return "\n".join(texts)
    return ""


def has_blockquote(text: str) -> bool:
    fenced = False
    for line in text.splitlines():
        if FENCE.match(line):
            fenced = not fenced
        elif not fenced and QUOTE.match(line):
            return True
    return False


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError:
        return
    if data.get("stop_hook_active"):
        return
    text = data.get("last_assistant_message") or last_text(data.get("transcript_path"))
    if has_blockquote(text):
        print(json.dumps({
            "decision": "block",
            "reason": "The reply uses a Markdown blockquote (`> `). It copies with a marker on every line. "
                      "Send the reply again with any text meant for pasting in a fenced code block "
                      "(tagged markdown when it holds Markdown) and no blockquote; see text-to-paste.md.",
        }))


if __name__ == "__main__":
    main()
