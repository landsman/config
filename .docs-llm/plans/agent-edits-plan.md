# Plan: agents edit code through Edit, not Python scripts

Agents in this setup change code mostly with a Python script that does
`s.replace(old, new)` on a file and writes it back, instead of calling Claude
Code's `Edit` tool. It is `Edit` reimplemented, minus a diff in the transcript
that can be reviewed, `Edit`'s refusal of a file that changed since it was read,
and a permission check per file. The share has been rising every week.

Editor MCPs (Zed, JetBrains) do not fix it. `Edit` already is the editing
primitive; Zed has no MCP server with edit tools, and JetBrains MCP adds only
semantic refactors (rename a symbol), which the built-in `LSP` tool covers too.

## What the transcripts show

Edits in worktrees, from every transcript since 12 October 2026, in closed weeks.
The unit is one replacement: a script with three `.replace(` calls, or a
`for old, new in [...]` list of three pairs, counts three; an `Edit` call counts
one. A script counts only when it both replaces text and writes a file. Left
out: calls whose result was an error or a hook's refusal, scripts that iterate
a file listing (`glob`, `os.walk`, `find`, `rg -l`, `xargs`: the many-file case
that should stay in Bash, see below), and scripts writing into a scratchpad or
`/tmp`. Method at the end.

| Week | Script replacements | `Edit` calls | Script share | Sessions | Script-first sessions |
|---|---|---|---|---|---|
| 12 to 18 Oct | 887 | 830 | 52 % | 67 | 55 % |
| 19 to 25 Oct | 2 626 | 649 | 80 % | 80 | 71 % |
| 26 Oct to 1 Nov | 1 493 | 515 | 74 % | 68 | 63 % |
| 2 to 8 Nov | 2 489 | 271 | 90 % | 57 | 88 % |

Sessions are counted when they made at least five edits. They are bimodal: one
session uses `Edit` almost only, the next scripts almost only. So the number to
watch is the share of **script-first sessions**, those with more than half of
their edits through scripts. A median would flip between the two modes on a
handful of sessions, and the pooled share moves with one large session.

By Claude Code release the share does not step up once and stay: the first
release in the window already ran at 79 %, the next two at 27 to 29 % (14 to
16 October), and every later one with 100+ edits between 48 and 96 %. So no
single release explains the rise, though a change in that window cannot be ruled
out either.

What it is **not**: the main-checkout guard. `checkout-guard.sh` refused an
`Edit` 9 times in the 30 days (tool results carrying its reason), against
thousands of script edits.

## Why, as far as it can be told

Hypotheses, none measured:

1. **Auto mode allows it.** Claude Code's built-in auto-mode prompt says small
   mechanical changes may go through "sed, heredocs, or short scripts" instead
   of `Edit`. 99.8 % of sessions in the window ran in auto mode, so there is no
   control group, and nothing shows that a rule can outweigh that prompt.
2. **The script skips the `Read`.** `Edit` refuses a file not read in the session;
   a script with `assert old in s` needs no read. A partial `Read` (offset and
   limit) is enough for `Edit`, which the agent may not know.
3. **Habit within a session.** The bimodal split fits an agent that copies its own
   earlier tool calls: once the first edit is a script, the rest follow.
4. **`Edit` mangles some text.** Writing this plan, `Edit` turned a literal
   `\u0027` in `old_string` and `new_string` into `'`, so the replacement first
   failed to match and then would have broken a quoted shell string. A script
   was the way out. One case, but the kind that teaches an agent to avoid `Edit`.

## Faster or cheaper?

Unknown, and not the point. A script makes several replacements and needs no
`Read`; the `Edit` route needs the file read first, so it may well cost more
tokens. The case for `Edit` is a reviewable diff and the stale-file check, not
speed. A change in many files at once stays a one-liner through Bash, because
forty `Read` plus `Edit` pairs cost far more.

## Steps, one at a time, each measured

### 1. Say how to edit, in a rule that is always loaded

Add a section to [worktrees](../../shared/.agents/rules/worktrees.md). It loads every
session and is about changing a repo, so no new rule file is needed. The
section says outright that, for a file in a repo, it **replaces** the auto-mode
prompt's allowance of "sed, heredocs, or short scripts" and its "the choice is
yours". A rule that only states a preference reads as one more opinion against
that prompt, and the measurement would then test a weaker rule than the one
meant.

- a change to a file is `Edit`; several places or files are several `Edit` calls
  in one response, one string everywhere is `replace_all`, a rewrite is `Write`;
- `Edit` needs the file read, and a partial `Read` of the lines around the change
  is enough;
- a failed `Edit` is fixed by reading again or widening `old_string`, not by a
  script;
- the same mechanical change in many files is `rg -l <pattern> | xargs perl -pi -e
  's/…/…/g'`. `perl -pi` behaves the same on macOS and Linux, `sed -i` does not;
- never a Python or JavaScript script that rewrites a file in the repo.

**Measure the two closed weeks after it lands. Keep it if script-first sessions
are below 55 % in both**, the lowest week of the baseline. The baseline rises
week on week, so beating its lowest point is a conservative bar.
Otherwise revert it, as [reporting data](../../shared/.agents/rules/reporting-data.md)
says for a neutral change, and go to step 2.

Watch alongside: a move from scripts to `perl -pi` on single files would read as
success but has the same missing diff. The method counts `inplace` calls
separately; a rise there of the size the scripts fell means the rule failed.

### 2. Only if step 1 did not move it: refuse the pattern

A `PreToolUse` hook on `Bash` that refuses one signature: an interpreter
(`python3`, `node`, `bun`, `ruby`) fed a heredoc or `-c`/`-e`, whose code both
replaces text (`.replace(`, `re.sub`) and writes a file (`open(…, 'w')`,
`write_text`, `writeFile`), run inside a git work tree under `~/projects/`. Its
reason points at `Edit` and the rule text from step 1. A read-only script, a
script writing into a scratchpad or `/tmp`, and a script iterating a file
listing (`glob`, `os.walk`, `find`, `rg -l`, `xargs`) pass. A `for` over a
written-out list of files or of `(old, new)` pairs does not pass: that is the
same edit in another shape, and the next one agents would reach for.

Before it is switched on: run the signature over 30 days of transcripts and
read 30 of its matches. More than one false positive means the signature is
narrowed first, because every false positive costs a round trip.

Where it goes is decided then, by [reuse before
adding](../../shared/.agents/rules/reuse-before-adding.md). The hooks that parse a
Bash command each do another job (`search-guard.ts` searches, `office-guard.sh`
office files, `checkout-guard.sh` the main checkout only), so a new
`bin/agents/edit-guard.ts` with its test is the likely answer, stated in the PR.

Measured like step 1, with the same bar.

## Not doing

- **Closing the Bash route around `checkout-guard.sh`.** Nine refusals in 30 days
  do not pay for a command parser, and judging by `cwd` would refuse a subagent
  that `cd`s into its worktree and every read-only `python3 -c` in a checkout.
  The hook's `ponytail:` comment stays as the record.
- **An editor MCP.** See the top.
- **A hook against Python in general.** Scripts that read data or write into a
  scratchpad are legitimate and common.

## Method

Every `tool_use` in assistant entries with a `timestamp` since the start date,
from `~/.claude/projects/**/*.jsonl`. A call counts only when its `tool_result`
is not `is_error`; a hook's refusal and a failed `Edit` both are. Bash commands
are classified by pattern. The place is `worktree` when the file path, the `cwd`
or the command contains `/.claude/worktrees/`; worktrees made elsewhere count as
another place, so the worktree numbers are a lower bound.

`edits.sh <since YYYY-MM-DD> <out dir>` writes `calls.tsv` and `errors.txt`:

```sh
#!/usr/bin/env bash
set -euo pipefail
since=$1
out=$(cd "$2" && pwd)
cd ~/.claude/projects
files=$(find . -name '*.jsonl' -newermt "$since")

# shellcheck disable=SC2086
rg --no-filename -F '"type":"tool_use"' $files | jq -r --arg since "$since" --arg home "$HOME" '
  select(.type=="assistant" and (.timestamp // "") >= $since) | . as $e
  | .message.content[]? | select(.type=="tool_use")
  | (if .name=="Bash" then
       (.input.command // "") as $c
       | if   ($c|test("\\b(python3?|node|bun|ruby)\\b[^|;]*(<<|\\s-[ce]\\s)")) and ($c|test("\\.replace\\(|re\\.sub\\(")) and ($c|test("open\\([^)]*[\"\u0027][wa]|write_text|writeFile|\\.write\\(")) then "script-write"
         elif ($c|test("\\b(g?sed)\\b[^|;&]*\\s-[a-zA-Z]*i|\\bperl\\b[^|;&]*\\s-[a-z]*i|\\byq\\b[^|;&]*\\s-i|awk -i inplace")) then "inplace"
         elif ($c|test("cat\\s*>\\s*[^&]|cat\\s*<<[^\\n]*>\\s*[^&/]|cat\\s*>>|\\btee\\s+(-a\\s+)?[^-/|\\s]")) then "heredoc-write"
         else empty end
     elif (.name|test("^(Edit|Write|MultiEdit)$")) then .name else empty end) as $class
  | (if .name=="Bash" then ($e.cwd // "") else (.input.file_path // "") end) as $p
  | (if   (($p|test("/\\.claude/worktrees/")) or (.name=="Bash" and ((.input.command // "")|test("\\.claude/worktrees/")))) then "worktree"
     elif ($p|test("^(/private)?/tmp|/var/folders/")) then "tmp"
     elif ($p|startswith($home + "/projects/")) then "checkout"
     else "other" end) as $place
  | (if .name=="Bash" then (.input.command // "") else "" end) as $c
  | ($c|[match("\\.replace\\(|re\\.sub\\(";"g")]|length) as $calls
  | (if ($c|test("\\bfor\\b[^\\n]*\\bin\\s*\\[")) then ($c|[match("(^|[\\[,\\s])\\(\\s*[\"\u0027]";"g")]|length) else 0 end) as $tuples
  | ([$calls, $tuples]|max) as $nrep
  | (if ($c|test("glob|os\\.walk|listdir|iterdir|xargs|\\bfind |rg -l|git ls-files")) then 1 else 0 end) as $loop
  | (if ($c|test("/tmp/|scratchpad|/var/folders/")) then 1 else 0 end) as $tmp
  | [$e.timestamp, .id, .name, $class, $place, $e.sessionId, $nrep, $loop, $tmp, ($e.version // "")] | @tsv' > "$out/calls.tsv"

# shellcheck disable=SC2086
rg --no-filename -F '"is_error":true' $files | jq -r '
  .message.content[]? | select(type=="object" and .type=="tool_result" and .is_error==true) | .tool_use_id' \
  | sort -u > "$out/errors.txt"
```

`share.awk` prints the weekly table. Run it in the out dir on time-sorted rows,
so a session is filed under the week of its first edit, not of the first file
`find` happened to return:
`sort -t$'\t' -k1,1 calls.tsv | awk -f share.awk errors.txt -`. Change the week
bounds in `week()` for a new window, and leave the current, still open week out:

```awk
function week(ts){ return ts<"2026-10-19"?"1":ts<"2026-10-26"?"2":ts<"2026-11-02"?"3":ts<"2026-11-09"?"4":"" }
BEGIN{FS="\t"}
NR==FNR{err[$1]=1;next}
err[$2] || $5!="worktree" {next}
{w=week($1); if(w=="") next; r=0; e=0
 if($4=="script-write" && $8==0 && $9==0 && $7>0) r=$7
 else if($3=="Edit"||$3=="MultiEdit") e=1
 else next
 R[w]+=r; E[w]+=e; SR[$6]+=r; SE[$6]+=e; if(!(($6) in SW)) SW[$6]=w}
END{
 for(s in SR) if(SR[s]+SE[s]>=5){ N[SW[s]]++; if(SR[s]/(SR[s]+SE[s])>0.5) F[SW[s]]++ }
 for(w in R) printf "week %s  script replacements=%d  Edit calls=%d  share=%.0f%%  sessions=%d  script-first=%.0f%%\n", w, R[w], E[w], 100*R[w]/(R[w]+E[w]), N[w], 100*F[w]/N[w]
}
```

Known bias: `script-write` misses a script saved to a file and then run, and the
pair count of a `for … in [...]` list is a pattern match, right on a spot check
of the idiom but not exact. A cold reviewer reran an earlier version of the
method and reproduced its counts; a spot check of 30 matches is part of every
new reading.
