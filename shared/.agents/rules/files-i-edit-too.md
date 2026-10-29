# Files I edit too

**Before writing to a document I can open myself — a Word file, a spreadsheet,
a presentation, a note outside git — check that it is still the version you
last read. If it is not, read it again and build on that.** I edit between your
turns, and a write based on the version in your context overwrites my changes
without a trace. That has already happened: a Word document regenerated from
the earlier version wiped out everything I had added in the meantime.

Git does not protect these files. Nothing shows a diff, and a `.docx` has no
history but the one you keep.

1. **Record the modification time** whenever you read or write the file:
   `date -r <file> +%s` (macOS and Linux alike).
2. **Compare it before every write.** Different, or never recorded: read the
   file again, and apply the change to what is there now, not to what you
   remember.
3. **Back it up before writing**, into the scratchpad with a timestamp:
   `cp -p <file> <scratchpad>/<name>.$(date +%Y%m%d-%H%M%S).<ext>`. Then a
   mistake is one `cp` back, not lost.
4. **Edit, do not regenerate.** A script that builds the whole document from
   scratch rebuilds it without my changes. Open the current file and change
   what was asked; rerun a generator only on a file nobody else has touched.
5. **An open file is not saved.** A lock file beside it (`~$name.docx`,
   `.~lock.name.odt#`) means I may have unsaved changes in the app — ask me to
   save and close it before writing.

When the check finds my changes, say so in one line, so I know they were kept.

In Claude Code a hook (`bin/agents/office-guard.sh`) backs up every office file
a Bash command names, into `~/.local/state/agent-backups/`, and refuses the
command once when the file changed since your last one or is open in an app.
It only sees a path written out in the command or in a script it runs, so the
rule still holds.
