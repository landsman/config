#!/usr/bin/env python3
"""UserPromptSubmit hook: a prompt that names a skill's topic gets a reminder to load it.

A skill opts in with `trigger-keywords:` in its SKILL.md frontmatter, comma
separated, matched case-insensitively as whole words. A trailing `*` matches
any ending, because Czech inflects: `commit*` catches "commitu" and "commity",
where a plain `commit` would not. Diacritics are dropped on both sides, so
`komentář*` also catches "komentar" typed without them. Only user skills
(~/.claude/skills, which is ~/.agents/skills) and the project's own
.claude/skills are read; a skill already loaded this session is not reminded of
again.

Adapted from skill-keyword-reminder in github.com/fprochazka/claude-code-plugins.
"""
import json
import os
import re
import sys
import unicodedata
from pathlib import Path


def fold(text: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFKD", text) if not unicodedata.combining(c))


def keywords(skill_md: Path) -> tuple[str, list[str]]:
    m = re.match(r"---\n(.*?)\n---", skill_md.read_text(encoding="utf-8"), re.S)
    meta = dict(line.split(":", 1) for line in (m.group(1) if m else "").splitlines() if ":" in line and not line.startswith(" "))
    name = meta.get("name", skill_md.parent.name).strip()
    return name, [fold(k.strip()) for k in meta.get("trigger-keywords", "").split(",") if k.strip()]


def pattern(words: list[str]) -> re.Pattern:
    parts = [re.escape(w[:-1]) + r"\w*" if w.endswith("*") else re.escape(w) + r"(?!\w)" for w in words]
    return re.compile(r"(?<!\w)(?:" + "|".join(parts) + ")", re.I)


def loaded(transcript: str | None) -> set[str]:
    try:
        # A transcript runs to a hundred MB; parse only the lines that can hold a Skill call.
        with open(transcript, encoding="utf-8") as f:
            lines = [line for line in f if '"Skill"' in line]
    except (OSError, TypeError):
        return set()
    names = set()
    for line in lines:
        try:
            content = json.loads(line).get("message", {}).get("content", [])
        except (json.JSONDecodeError, AttributeError):
            continue
        for item in content if isinstance(content, list) else []:
            if isinstance(item, dict) and item.get("name") == "Skill":
                names.add(item.get("input", {}).get("skill", ""))
    return names


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError:
        return
    prompt = fold(data.get("prompt", ""))
    dirs = [Path.home() / ".claude" / "skills"]
    if os.environ.get("CLAUDE_PROJECT_DIR"):
        dirs.append(Path(os.environ["CLAUDE_PROJECT_DIR"]) / ".claude" / "skills")
    hits = []
    for skill_md in sorted(p for d in dirs for p in d.glob("*/SKILL.md")):
        try:
            name, words = keywords(skill_md)
        except (OSError, UnicodeDecodeError):
            continue
        if words and pattern(words).search(prompt):
            hits.append(name)
    done = loaded(data.get("transcript_path")) if hits else set()
    hits = [h for h in dict.fromkeys(hits) if h not in done]
    if hits:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": "\n".join(f"IMPORTANT: load the {h} skill before acting on this prompt." for h in hits),
        }}))


if __name__ == "__main__":
    main()
