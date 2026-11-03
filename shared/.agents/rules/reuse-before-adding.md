# Reuse before adding

**Before a new file — a hook, a script, a Make target, a rule, a skill, a
component, a helper — search the repo for one that already does a neighbouring
job, and extend it if it can be extended.** A new file is the last answer, not
the first.

Two things that do one job drift apart: one gets the fix, the other keeps the
bug, and the next session finds both and has to guess which is meant. It has
happened with hooks: a second SendUserFile hook was written beside
`bin/agents/send-files.ts`, which already handled sending a file, and had to be
folded back into it.

- **Search by what it does, not by the name you would give it**: the tool or
  event it hooks (`SendUserFile`, `PreToolUse`), the command it wraps, the
  file it reads. `git grep` over the repo, and the index of the folder it
  would go in (`bin/agents/`, `shared/.agents/rules/`, the skills list).
- **Extend when the existing one covers the same thing**, the same tool, the
  same files, the same reader: a second event in one hook, a flag on one
  script, a section in one rule, a variant of one component.
- **Add a new one only when extending would make the old one do two
  unrelated jobs**, and say in one line which one you found and why it did not
  fit: in the reply, and in the PR body.

The same holds in a client's repo: a `Modal` the app already has, a
`Styles.*` constant, a `make` target, before a second one.
