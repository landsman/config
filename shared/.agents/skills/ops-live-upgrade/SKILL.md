---
name: live-upgrade
description: Load before changing something live that is hard to undo — upgrading a self-hosted service or its major version, running a migration on real data, moving or restoring a service, replacing a database or a volume — and before writing the runbook, checklist or PR body for one. Carries reading the real release notes, checking the runbook against the box, a backup that can really bring it back, the order of the steps, what counts as verified, and how to report it.
trigger-keywords: upgrad*, updat*, rollback, restore, obnov*, záloh*, backup*
---

# Changing something live that is hard to undo

**Before the step you cannot undo, prove what it touches and prove the way back.
Everything before that step is cheap; everything after it is not.** A confident
plan written from the repo is the usual failure: the box differs from the repo,
and the announcement differs from the release notes.

Each step that touches the live service needs my go-ahead for that service, once
([everything as code](../../rules/everything-as-code.md) still applies: what ran
is what is in a repo, in the same session).

## Before

1. **Read the full release notes, every version being crossed.** The blog post
   is a selection. Open the breaking section and the patch releases since; a
   newer patch may be a security fix, so go to it rather than to the `.0`. Check
   the image exists.
2. **Turn each breaking change into a question about this instance**, and answer
   it there. "No hook in the repo" says nothing about hooks kept in the database,
   and a config file on the box is not in the repo.
3. **Ask the system, not the UI.** A read-only query or the API beats a checklist
   item for a human. Keep it read-only, and keep secrets out of the output: print
   key names and hide the values.
4. **Check the runbook on the box before anyone relies on it.** How do files get
   there (is there a `.git` at all)? What differs from the repo? What else runs
   there, and which jobs are in flight? Write what you saw, not what should be.
5. **Measure the cost.** "Short outage" is a number from a real run, including
   any scheduled job the change makes slower.

## The way back

6. **Take the backup immediately before the step**, with writers stopped, and
   start them again even if the copy fails.
7. **List what the backup leaves out**: `.env`, the old version's pin, anything
   registered elsewhere. Know whether all data paths are inside what was copied,
   and whether external storage exists.
8. **Check it**: the archive opens, the database and the object count match the
   source. A checksum proves the transfer, not the contents. Say whether a restore
   was tried; if not, it is unproven, and that goes in the report.
9. **Keep a copy off the array that holds the data.** On the same disks it survives
   a mistake, not a failure. Confirm the copy still exists just before the step, and
   tell me where it is; it holds secrets, so restrict its permissions.
10. **Write the rollback down with real file names**, and say what it loses.

## The change

11. **Pull first, then stop**, so the outage is not spent downloading.
12. **One component at a time, the server before its clients.** Check each before
    the next, and do not restart a client that has a job running.
13. **On a failure, stop and report.** Do not roll back on your own unless that was
    agreed: it discards data, and the error may be the smaller loss.

## Verified means

14. **Exercise it, do not just ask if it is up.** A health check proves the process
    answers. Read the log for errors and migrations, compare counts before and
    after, and run a real job through every integration. What could not be run is
    listed as unverified, not implied to work.
15. **A check that printed nothing is not a pass.** Suppressed errors and an
    unsupported flag read as zero; a failed command reads as a clean result. Take
    a second reading when a number decides something.

## Report

Give the outcome first, then what was verified and how, what was not, the backup's
path, and what is still open: an unmerged PR while the box runs its files, a docs
step found wrong, and what happens at the next scheduled run.
