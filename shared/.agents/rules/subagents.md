# Subagents

A subagent starts with none of the context you built up with me, so most of what
goes wrong with one is either paying for that discovery twice or believing a
result it never produced.

- **The cheapest model that can do the subtask**, never your own by habit
  (a fork inherits yours; pick a typed agent when the tier matters). A
  mechanical step — grep the logs, run one query, run the tests and summarise —
  is the small model. Real work — a code change, debugging, research over
  several steps — is the default one. The top model only when the subtask itself
  is the hard part: an architecture call, a cross-system bug, a concurrency
  argument. In doubt between two tiers, the lower one.
- **When the method is not known yet, probe before running the whole thing.**
  A subagent handed the full problem takes the first approach that comes to
  mind and runs it against everything; when that approach is wrong it fights for
  an hour and comes back with nothing. Ask for the method on a small slice
  instead — one tenant, one day, `LIMIT 10` — with the evidence that it worked
  and what it ruled out, and stop there. Judge it, then send the full run to
  **the same subagent**.
- **Resume a subagent rather than spawn a new one** when the next task touches
  the same system. It already knows the schema, the working query and the dead
  ends; a fresh one finds them again. Start fresh only for unrelated work, for a
  reviewer that has to come in cold, or near the old one's context limit.
- **Hand it the skill and the files, not a retelling.** The prompt names the
  skill to load before the first command, and points at a plan or a log by its
  path instead of pasting it in.
- **A task that was killed, timed out, or is still running in the background
  has not passed.** Exit code 143 is not a pass. Read the output back before
  reporting on it, and never carry a "green" forward from a run you did not see
  finish.
- **Background work goes through the harness's own mechanism** (in Claude
  Code `run_in_background` or a background agent), never `nohup`, `setsid` or
  a trailing `&`. A detached process is invisible in the session and nothing
  kills it when the session ends; `make dev-server-kill` exists because of
  exactly that.
