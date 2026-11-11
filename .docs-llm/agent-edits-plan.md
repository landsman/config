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
The unit is one replacement: a script with three `.replace(` counts three, an
`Edit` call counts one. Left out: calls whose result was an error or a hook's
refusal, scripts that loop or glob over many files (the case that should stay in
Bash, see below), scripts writing into a scratchpad or `/tmp`, and scripts with
no replace call. Method at the end.

| Week | Script replacements | `Edit` calls | Script share | Sessions | Median session share | Middle half of sessions |
|---|---|---|---|---|---|---|
| 12 to 18 Oct | 728 | 857 | 46 % | 67 | 60 % | 0 to 98 % |
| 19 to 25 Oct | 1 815 | 649 | 74 % | 78 | 90 % | 30 to 100 % |
| 26 Oct to 1 Nov | 1 092 | 515 | 68 % | 64 | 75 % | 20 to 100 % |
| 2 to 8 Nov | 1 863 | 271 | 87 % | 57 | 98 % | 73 to 100 % |

Sessions are counted when they made at least five edits. They are bimodal: one
session uses `Edit` almost only, the next scripts almost only, so the per-session
median is the number to watch, not the pooled share, which one large session can
move.

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

## Faster or cheaper?

Unknown, and not the point. A script averages 2.4 replacements and needs no
`Read`; the `Edit` route needs the file read first, so it may well cost more
tokens. The case for `Edit` is a reviewable diff and the stale-file check, not
speed. A change in many files at once stays a one-liner through Bash, because
forty `Read` plus `Edit` pairs cost far more.

## Steps, one at a time, each measured

### 1. Say how to edit, in a rule that is always loaded

Add a section to [worktrees](../shared/.agents/rules/worktrees.md). It loads every
session and is about changing a repo, so no new rule file is needed:

- a change to a file is `Edit`; several places or files are several `Edit` calls
  in one response, one string everywhere is `replace_all`, a rewrite is `Write`;
- `Edit` needs the file read, and a partial `Read` of the lines around the change
  is enough;
- a failed `Edit` is fixed by reading again or widening `old_string`, not by a
  script;
- the same mechanical change in many files is `rg -l <pattern> | xargs perl -pi -e
  's/…/…/g'`. `perl -pi` behaves the same on macOS and Linux, `sed -i` does not;
- never a Python or JavaScript script that rewrites a file in the repo.

**Measure the two closed weeks after it lands. Keep it if the median session
share is below 60 % in both**, the lowest weekly median of the baseline. The
baseline rises week on week, so beating its lowest point is a conservative bar.
Otherwise revert it, as [reporting data](../shared/.agents/rules/reporting-data.md)
says for a neutral change, and go to step 2.

Watch alongside: a move from scripts to `perl -pi` on single files would read as
success but has the same missing diff. The method counts `inplace` calls
separately; a rise there of the size the scripts fell means the rule failed.

### 2. Only if step 1 did not move it: refuse the pattern

A `PreToolUse` hook on `Bash` that refuses one signature: an interpreter
(`python3`, `node`, `bun`, `ruby`) fed a heredoc or `-c`/`-e`, whose code both
replaces text (`.replace(`, `re.sub`) and writes a file (`open(…, 'w')`,
`write_text`, `writeFile`), with no loop or glob, run inside a git work tree
under `~/projects/`. Its reason points at `Edit` and the rule text from step 1.
A read-only script, a script writing into a scratchpad or `/tmp`, and a loop over
many files pass.

Before it is switched on: run the signature over 30 days of transcripts and
read 30 of its matches. More than one false positive means the signature is
narrowed first, because every false positive costs a round trip.

Where it goes is decided then, by [reuse before
adding](../shared/.agents/rules/reuse-before-adding.md). The hooks that parse a
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
       | if   ($c|test("\\b(python3?|node|bun|ruby)\\b[^|;]*(<<|\\s-[ce]\\s)")) and ($c|test("write|open\\([^)]*[\"\u0027][wa]|write_text|writeFile|re\\.sub|\\.replace\\(")) then "script-write"
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
  | ($c|[match("\\.replace\\(|re\\.sub\\(";"g")]|length) as $nrep
  | (if ($c|test("\\bfor\\b[^\\n]*\\bin\\b|glob|os\\.walk|xargs")) then 1 else 0 end) as $loop
  | (if ($c|test("/tmp/|scratchpad|/var/folders/")) then 1 else 0 end) as $tmp
  | [$e.timestamp, .id, .name, $class, $place, $e.sessionId, $nrep, $loop, $tmp] | @tsv' > "$out/calls.tsv"

# shellcheck disable=SC2086
rg --no-filename -F '"is_error":true' $files | jq -r '
  .message.content[]? | select(type=="object" and .type=="tool_result" and .is_error==true) | .tool_use_id' \
  | sort -u > "$out/errors.txt"
```

`share.awk`, run as `awk -f share.awk errors.txt calls.tsv`, prints the weekly
table and writes per-session shares to `sessions.tsv`. Change the week bounds in
`week()` for a new window, and leave the current, still open week out:

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
 for(w in R) printf "week %s  script replacements=%d  Edit calls=%d  share=%.0f%%\n", w, R[w], E[w], 100*R[w]/(R[w]+E[w])
 for(s in SR) if(SR[s]+SE[s]>=5) printf "%s\t%.3f\n", SW[s], SR[s]/(SR[s]+SE[s]) > "sessions.tsv"
}
```

Median per week: `for w in 1 2 3 4; do awk -v w=$w '$1==w{print $2}' sessions.tsv | sort -n | awk '{a[NR]=$1} END{print a[int((NR+1)/2)]}'; done`.

Known bias: `script-write` misses a script saved to a file and then run, and a
session is filed under the week of its first edit. A cold reviewer reran an
earlier version of the method and reproduced its counts; a spot check of 30 matches is part of every
new reading.
