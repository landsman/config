#!/usr/bin/env python3
"""Stop hook: a file the reply names for me to look at gets sent, not just named.

A path in the reply opens nothing in the terminal, and a phone following the
session has no file behind it at all. When this turn's text names an existing
screenshot, PDF, page, office file or video that SendUserFile never sent in this
session, the stop is blocked once with the list, so the model sends them. A path
to source code is a reference into a repo, not something to look at, and passes.

`stop_hook_active` is set on the stop that follows a block, so a turn that cannot
send (no SendUserFile in this harness) is held at most once.
"""
from __future__ import annotations

import json
import os
import re
import sys

LOOK = re.compile(
    r"(?<![\w.~/-])((?:/|~/)[^\s`'\"()<>\[\]{}|*]+?\.(?:png|jpe?g|gif|webp|svg|pdf|html?|xlsx|docx|pptx|mp4|mov))(?![\w-])",
    re.I,
)
TAIL = 4 * 1024 * 1024  # bytes; a turn fits, and a transcript runs to a hundred MB


def entries(lines: list[str]) -> list[dict]:
    out = []
    for line in lines:
        try:
            e = json.loads(line)
        except json.JSONDecodeError:
            continue
        if e.get("type") in ("user", "assistant") and not e.get("isSidechain"):
            out.append(e)
    return out


def content(entry: dict) -> list:
    c = (entry.get("message") or {}).get("content")
    return [{"type": "text", "text": c}] if isinstance(c, str) else c if isinstance(c, list) else []


def is_prompt(entry: dict) -> bool:
    """A prompt the user typed, not a tool result or a reminder the harness injected."""
    if entry.get("type") != "user" or entry.get("isMeta"):
        return False
    return any(isinstance(i, dict) and i.get("type") in ("text", "image") for i in content(entry))


def turn_text(transcript: str) -> str:
    """What the assistant wrote since the last prompt."""
    with open(transcript, "rb") as f:
        f.seek(max(0, os.path.getsize(transcript) - TAIL))
        lines = f.read().decode("utf-8", "replace").splitlines()
    turn = []
    for e in reversed(entries(lines)):
        if is_prompt(e):
            break
        turn.append(e)
    return "\n".join(
        i.get("text", "") for e in turn if e["type"] == "assistant" for i in content(e) if isinstance(i, dict) and i.get("type") == "text"
    )


def sent(transcript: str) -> set[str]:
    """Every file SendUserFile sent in the session, resolved."""
    with open(transcript, encoding="utf-8", errors="replace") as f:
        lines = [line for line in f if '"SendUserFile"' in line]
    files = set()
    for e in entries(lines):
        for i in content(e):
            if isinstance(i, dict) and i.get("name") == "SendUserFile":
                files.update(os.path.realpath(os.path.expanduser(p)) for p in (i.get("input") or {}).get("files") or [])
    return files


def unsent(transcript: str) -> list[str]:
    named = dict.fromkeys(LOOK.findall(turn_text(transcript)))
    done = sent(transcript)
    return [p for p in named if os.path.isfile(os.path.expanduser(p)) and os.path.realpath(os.path.expanduser(p)) not in done]


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError:
        return
    transcript = data.get("transcript_path")
    if data.get("stop_hook_active") or not transcript or not os.path.isfile(transcript):
        return
    missing = unsent(transcript)
    if missing:
        reason = (
            "The reply names files for the user to look at, but a path opens nothing in their terminal and does not reach "
            "a phone. Send them with SendUserFile (images with display: render), then finish; if that tool is not "
            "available here, say so instead:\n" + "\n".join(missing)
        )
        print(json.dumps({"decision": "block", "reason": reason}))


if __name__ == "__main__":
    main()
