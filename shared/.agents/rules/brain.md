# Brain

My long-term memory lives in `$BRAIN_DIR`, a private repo (`make brain` in
the config repo sets it):
`raw/` for sources as they arrived, `wiki/` for pages compiled from them.
The how is in the `brain` skill; load it before touching the repo.
**Empty `$BRAIN_DIR` in your shell** (a harness whose shell never read `.zshrc` or `.bashrc`)
turns every path below into `/wiki`, which finds nothing without an error. Read
it with `~/projects/landsman/config/bin/agents/brain-dir.sh get` first.

- **Before researching something, look there first** — `wiki/index.md`, then
  `grep -ril <term> $BRAIN_DIR/wiki`. A finding I already paid
  for should not be paid for twice.
- **After a research, file it there, unasked, in the same turn.** Web searches,
  tool comparisons, an investigation whose conclusion outlives the session — it
  goes in as a source and gets compiled into the wiki. A finding left in the
  transcript is gone by the next session. **A subagent does not** — it
  reports its findings to its caller, which files them, unless the caller
  asked it to write there itself.
- **"Remember this", "save it to the brain"** goes there, not into the
  per-project agent memory — that one is scoped to a single repo and invisible
  to every other agent.
- Nothing from it goes into a public repo, commit or doc; see
  [where the repos live](where-repos-live.md).
