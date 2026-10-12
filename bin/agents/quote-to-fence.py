#!/usr/bin/env python3
"""MessageDisplay hook: a blockquote is shown as a code block, so it copies without `> `.

A blockquote renders in the terminal with a bar or `> ` on every line, and the
copy takes it along. This rewrites only what is shown: a run of quoted lines
loses its markers and is wrapped in a fence, which copies clean and keeps any
Markdown inside it raw. The transcript and what the model sees stay as written.

Claude Code calls the hook once per batch of completed lines and renders the
batches as one Markdown text, so a fence opened in one batch is closed in a
later one. That needs the state of the message so far (is it inside a fence of
its own, is a quote run of ours still open), kept in a small file per message.
The calls for one message run concurrently, observed on 2.1.296, so each call
waits for the previous index to have written its state before reading it. If
that does not happen in time, the rest of the message is shown as it came.
"""
from __future__ import annotations

import json
import os
import re
import sys
import tempfile
import time
from pathlib import Path

QUOTE = re.compile(r"^ {0,3}> ?")
FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})(.*)$")
STATE = Path(tempfile.gettempdir()) / "claude-quote-to-fence"
WAIT = 5.0  # seconds; Claude Code's own timeout for this event is 10


def longest_ticks(line: str) -> int:
    return max((len(r) for r in re.findall(r"`+", line)), default=0)


def rewrite(delta: str, fence: str | None, ours: str | None, final: bool) -> tuple[str, str | None, str | None]:
    """Return the text to show, the message's own open fence, and our open quote fence."""
    out = []
    for line in delta.splitlines(keepends=True):
        m = FENCE.match(line)
        if fence is None and QUOTE.match(line) and not m:
            body = QUOTE.sub("", line, count=1)
            body = body if body.endswith("\n") else body + "\n"
            if ours and longest_ticks(body) >= len(ours):
                out.append(ours + "\n")
                ours = None
            if ours is None:
                ours = "`" * max(3, longest_ticks(body) + 1)
                out.append(ours + "markdown\n")
            out.append(body)
            continue
        if ours:
            out.append(ours + "\n")
            ours = None
        if fence is None:
            if m and not (m.group(1)[0] == "`" and "`" in m.group(2)):
                fence = m.group(1)
        # CommonMark: the closer is the same character, at least as long, with nothing after it.
        elif m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence) and not m.group(2).strip():
            fence = None
        out.append(line)
    if ours and final:
        out.append(ours + "\n")
        ours = None
    return "".join(out), fence, ours


def previous(state: Path, index: int) -> dict | None:
    """The state left by batch index-1, waiting for it while that batch is still running."""
    if index == 0:
        return {"fence": None, "ours": None}
    deadline = time.monotonic() + WAIT
    while time.monotonic() < deadline:
        try:
            s = json.loads(state.read_text(encoding="utf-8"))
            if s.get("next") == index:
                return s
        except (OSError, json.JSONDecodeError):
            pass
        time.sleep(0.01)
    return None


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError:
        return
    delta = data.get("delta") or ""
    message = re.sub(r"[^\w-]", "", str(data.get("message_id", "")))
    index, final = data.get("index", 0), bool(data.get("final"))
    if not message:
        shown, _, _ = rewrite(delta, None, None, True)
    else:
        STATE.mkdir(mode=0o700, exist_ok=True)
        state = STATE / message
        s = previous(state, index)
        # Lost track (a batch timed out or failed): show the rest as it came, and tell
        # the later batches so, rather than have each of them wait out WAIT too.
        broken = s is None or s.get("broken", False)
        if broken:
            shown, fence, ours = delta, None, None
        else:
            shown, fence, ours = rewrite(delta, s.get("fence"), s.get("ours"), final)
        if final:
            state.unlink(missing_ok=True)
        else:
            tmp = state.with_suffix(".tmp")
            tmp.write_text(json.dumps({"next": index + 1, "fence": fence, "ours": ours, "broken": broken}), encoding="utf-8")
            tmp.replace(state)
    if shown != delta:
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "MessageDisplay", "displayContent": shown}}))


if __name__ == "__main__":
    os.umask(0o077)
    main()
