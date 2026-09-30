---
paths:
  - "**/.agents/rules/**"
  - "**/.agents/skills/**"
  - "**/.claude/rules/**"
  - "**/.claude/skills/**"
  - "**/SKILL.md"
  - "**/AGENTS.md"
  - "**/CLAUDE.md"
---

# Writing for an agent's context

**A rule, a skill or a reference an agent reads is written in layers, so a
session pays for the item it is working on and not for the whole list.**

Whatever gets loaded is paid for in tokens whether or not the task needed it,
and again on every turn it stays in context. A checklist of ninety points loaded
to fix one of them is eighty-nine points of waste, and it pushes out the code the
agent was supposed to be looking at.

1. **The trigger** — a skill's `description`, a rule's `paths:`, a row in an
   index. Every session pays for it, so it says when to load and nothing else.
2. **The list** — what loads on the trigger. Numbered, one sentence per item,
   each starting with an identifier. Enough to tell which item applies, not
   enough to apply it: no explanation, no example, no exceptions.
3. **The detail** — one section per item, opened only while that item is being
   worked on, and never read whole. The list says so, and gives the command:

       awk '/^## 1\.4\.3 /{f=1;print;next} /^## /{f=0} f' criteria.md

What makes the third layer reachable without reading it:

- **The identifier opens the heading**, and every item sits at the same heading
  level — `## 1.4.3 Contrast (Minimum)` — so one command extracts any of them.
- **The detail file says at its top that it is not to be read whole.** A file
  that looks like a page gets read like one.
- **A section stands alone.** If item 12 only makes sense after item 11, the
  agent loads both, and then the file.
- **The list and the detail come from one source**, or a check compares them. A
  line with no section behind it is a dead end found mid-task.

The accessibility criteria in the brain are the precedent: 86 of them, 23 803
words on disk by `wc -w`. The half of the list that is required is 1 263 words
and one criterion's section is 379, so working on one costs about 7 % of the
whole.

**Do not split what is short.** Below roughly 400 words a second file costs a
tool call to save nothing; the layers are for a reference of dozens of items,
not for a rule of three paragraphs. The same goes for a rule that loads
unconditionally: it holds what has to be known *before* the mistake, and the long
form moves to a skill, the way `commit-messages` does it.

Measure before deciding: `wc -w` on what loads at the trigger, against what is
on disk.
